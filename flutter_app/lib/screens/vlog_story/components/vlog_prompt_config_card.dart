import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../controllers/vlog_story_controller.dart';
import '../models/vlog_segment_model.dart';

class VlogPromptConfigCard extends StatelessWidget {
  final VlogStoryState state;
  final VlogStoryController controller;

  const VlogPromptConfigCard({
    super.key,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── SECTION 1: PHONG CÁCH KỂ CHUYỆN ──
          _buildSectionCard(
            context,
            icon: Icons.psychology_rounded,
            title: '1. Định Hướng & Phong Cách Kể',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tự động 100%', style: TextStyle(fontSize: 11.5, color: c.textMuted)),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: state.isAutoMode,
                    activeColor: AppColors.primary,
                    onChanged: (val) => controller.setAutoMode(val),
                  ),
                ),
              ],
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!state.isAutoMode) ...[
                  Text(
                    'Chọn tone giọng câu chuyện phù hợp với nhịp hình ảnh:',
                    style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStyleCard(VlogStoryStyle.dailyChill, c),
                      const SizedBox(width: 8),
                      _buildStyleCard(VlogStoryStyle.cinematic, c),
                      const SizedBox(width: 8),
                      _buildStyleCard(VlogStoryStyle.humorous, c),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chế độ tự động: AI sẽ tự cảm nhận góc quay, ánh sáng & màu sắc để chọn nhịp kể tối ưu nhất.',
                            style: TextStyle(fontSize: 11, color: c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── SECTION 2: GỢI Ý CỐT TRUYỆN / PROMPT TÙY BIẾN ──
          _buildSectionCard(
            context,
            icon: Icons.edit_note_rounded,
            title: '2. Thông Điệp Kịch Bản (Tùy Chọn)',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Suggestion Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPromptChip('🏕️ Du lịch dã ngoại chill', c),
                      const SizedBox(width: 6),
                      _buildPromptChip('🍳 Nấu ăn gia đình ấm cúng', c),
                      const SizedBox(width: 6),
                      _buildPromptChip('☕ Cà phê một mình hoài niệm', c),
                      const SizedBox(width: 6),
                      _buildPromptChip('🏙️ Dạo phố hoàng hôn', c),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLines: 3,
                  controller: TextEditingController(text: state.customPrompt)
                    ..selection = TextSelection.fromPosition(TextPosition(offset: state.customPrompt.length)),
                  onChanged: (val) => controller.setCustomPrompt(val),
                  decoration: InputDecoration(
                    hintText: 'Nhập gợi ý nội dung (VD: Kể về cảm giác bình yên của một buổi sớm tự pha cà phê, giọng điệu sâu lắng...)',
                    hintStyle: TextStyle(fontSize: 11.5, color: c.textMuted.withOpacity(0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: c.surfaceLight.withOpacity(0.2),
                    suffixIcon: state.customPrompt.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: 'Xóa gợi ý',
                            onPressed: () => controller.setCustomPrompt(''),
                          )
                        : null,
                  ),
                  style: TextStyle(fontSize: 12.5, color: c.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── SECTION 3: LÕI AI THỊ GIÁC (ENGINE) ──
          _buildSectionCard(
            context,
            icon: Icons.memory_rounded,
            title: '3. Lõi AI Thị Giác (Vision Engine)',
            content: Row(
              children: [
                Expanded(
                  child: _buildEngineOption(
                    engine: VlogStoryEngine.gemini,
                    title: 'Google Gemini Files API',
                    desc: '1-Pass siêu tốc ~20s, nhận diện video toàn cảnh mượt mà.',
                    c: c,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildEngineOption(
                    engine: VlogStoryEngine.ollama,
                    title: 'Ollama Vision Local',
                    desc: 'Chạy offline bảo mật cao qua mô hình cục bộ.',
                    c: c,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── SECTION 4: HÒA ÂM NHẠC NỀN BGM & DUCKING ──
          _buildSectionCard(
            context,
            icon: Icons.music_note_rounded,
            title: '4. Nhạc Nền BGM & Smart Ducking',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: c.surfaceLight.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.audio_file_outlined, size: 16, color: state.bgmPath != null ? AppColors.primary : c.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                state.bgmPath != null ? p.basename(state.bgmPath!) : 'Chưa chọn nhạc nền (Sử dụng audio gốc)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: state.bgmPath != null ? c.textPrimary : c.textMuted,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (state.bgmPath != null)
                              InkWell(
                                onTap: () => controller.setBgmPath(null),
                                child: Icon(Icons.close, size: 14, color: c.textMuted),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.surfaceLight,
                        foregroundColor: c.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: c.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 15),
                      label: const Text('Chọn BGM', style: TextStyle(fontSize: 11.5)),
                      onPressed: () async {
                        final res = await FilePicker.platform.pickFiles(type: FileType.audio);
                        if (res != null && res.files.single.path != null) {
                          controller.setBgmPath(res.files.single.path!);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Âm lượng BGM: ${(state.bgmVolume * 100).round()}%', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                    Expanded(
                      child: Slider(
                        value: state.bgmVolume,
                        min: 0.05,
                        max: 0.60,
                        divisions: 11,
                        activeColor: AppColors.primary,
                        onChanged: (val) => controller.setBgmVolume(val),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── SECTION 5: NÚT HÀNH ĐỘNG CHỦ LỰC ──
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: state.isGeneratingScript
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                state.isGeneratingScript ? 'Đang Phân Tích Video & Tạo Kịch Bản...' : '✨ Tạo Kịch Bản AI Phân Cảnh',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: (state.isProcessing || state.videoPath.isEmpty)
                  ? null
                  : () => controller.generateScript(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    Widget? trailing,
    required Widget content,
  }) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 15, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: c.textPrimary),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _buildPromptChip(String text, dynamic c) {
    return InkWell(
      onTap: () => controller.setCustomPrompt(text),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.surfaceLight.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withOpacity(0.8)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 10.5, color: c.textSecondary),
        ),
      ),
    );
  }

  Widget _buildStyleCard(VlogStoryStyle style, dynamic c) {
    final isSelected = state.style == style;
    return Expanded(
      child: InkWell(
        onTap: () => controller.setStyle(style),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.12) : c.surfaceLight.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : c.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 18, color: isSelected ? AppColors.primary : c.textMuted),
              const SizedBox(height: 4),
              Text(
                style.label.split(' / ').first,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primary : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEngineOption({
    required VlogStoryEngine engine,
    required String title,
    required String desc,
    required dynamic c,
  }) {
    final isSelected = state.engine == engine;
    return InkWell(
      onTap: () => controller.setEngine(engine),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : c.surfaceLight.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : c.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 14,
                  color: isSelected ? AppColors.primary : c.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? AppColors.primary : c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: TextStyle(fontSize: 9.5, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
