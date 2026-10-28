import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/app_colors.dart';
import '../../core/providers.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/tool_header_toolbar.dart';
import 'controllers/tts_studio_controller.dart';
import 'models/tts_models.dart';

class TtsStudioScreen extends ConsumerStatefulWidget {
  final Function(int)? onNavigateTab;

  const TtsStudioScreen({
    super.key,
    this.onNavigateTab,
  });

  @override
  ConsumerState<TtsStudioScreen> createState() => _TtsStudioScreenState();
}

class _TtsStudioScreenState extends ConsumerState<TtsStudioScreen> {
  final TextEditingController _rawScriptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final currentText = ref.read(ttsStudioProvider).rawScript;
    if (currentText.isNotEmpty) {
      _rawScriptController.text = currentText;
    }
  }

  @override
  void dispose() {
    _rawScriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttsStudioProvider);
    final controller = ref.read(ttsStudioProvider.notifier);
    final activeProject = ref.watch(activeProjectProvider);

    // Keep controller text in sync if rawScript changed externally or cleared
    if (_rawScriptController.text != state.rawScript) {
      _rawScriptController.text = state.rawScript;
      _rawScriptController.selection = TextSelection.fromPosition(
        TextPosition(offset: _rawScriptController.text.length),
      );
    }

    final rawWords = state.rawScript.trim().isEmpty ? 0 : state.rawScript.trim().split(RegExp(r'\s+')).length;
    final estMinutes = (rawWords / (140 * state.defaultSpeed)).clamp(0.0, 999.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── 1. SUB-HEADER TOOLBAR (44PX) ─────────────────────────────
          ToolHeaderToolbar(
            icon: const Icon(Icons.record_voice_over_outlined, color: AppColors.primary, size: 16),
            title: 'TTS Studio (Tạo Giọng Đọc)',
            breadcrumb: activeProject != null ? 'Dự án: $activeProject' : 'Kịch Bản Tự Do',
            badge: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 0.8),
              ),
              child: Text(
                '${state.segments.length} đoạn câu',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
            actions: [
              AppButton(
                label: 'Nhập Kịch Bản (.txt)',
                icon: Icons.file_upload_outlined,
                variant: AppButtonVariant.primary,
                height: 28,
                fontSize: 11,
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    dialogTitle: 'Chọn tệp kịch bản (.txt, .md)',
                    type: FileType.custom,
                    allowedExtensions: ['txt', 'md', 'srt', 'vtt'],
                  );
                  if (result != null && result.files.single.path != null) {
                    await controller.importScriptFile(result.files.single.path!);
                  }
                },
              ),
              const SizedBox(width: 6),
              AppButton(
                label: 'Mẫu Tiếng Anh (US/UK)',
                icon: Icons.language,
                variant: AppButtonVariant.ghost,
                height: 28,
                fontSize: 11,
                onPressed: () => controller.loadSampleEnglishScript(),
              ),
              const SizedBox(width: 6),
              AppButton(
                label: 'Mẫu Tiếng Việt',
                icon: Icons.flag,
                variant: AppButtonVariant.ghost,
                height: 28,
                fontSize: 11,
                onPressed: () => controller.loadSampleVietnameseScript(),
              ),
              const SizedBox(width: 6),
              AppButton(
                label: 'Làm Mới',
                icon: Icons.refresh,
                variant: AppButtonVariant.secondary,
                height: 28,
                fontSize: 11,
                onPressed: () {
                  _rawScriptController.clear();
                  controller.clearAll();
                },
              ),
            ],
          ),

          // ── 2. MAIN BODY (SPLIT VIEW) ────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── PANEL TRÁI: NHẬP LIỆU & CẤU HÌNH (400PX) ──
                Container(
                  width: 400,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(right: BorderSide(color: AppColors.border, width: 1)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Kịch bản
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '1. KỊCH BẢN GỐC',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                            ),
                            Text(
                              '$rawWords từ • ~${estMinutes.toStringAsFixed(1)} phút',
                              style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Text Area Nhập Kịch Bản
                        Container(
                          height: 220,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: TextField(
                            controller: _rawScriptController,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Dán hoặc gõ kịch bản tại đây...\n\n(Hệ thống sẽ tự động tách câu theo dấu chấm, ngắt dòng hoặc phân tách thông minh).',
                              hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(12),
                            ),
                            onChanged: (text) => controller.setRawScript(text),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Nút Hành Động Phân Tách Trực Tiếp Dưới Ô Nhập
                        AppButton(
                          label: '⚡ Phân Tách Kịch Bản Thành Câu',
                          icon: Icons.splitscreen,
                          variant: AppButtonVariant.primary,
                          height: 36,
                          fontSize: 12,
                          isLoading: state.isSplitting,
                          onPressed: () => controller.splitScript(),
                        ),

                        const SizedBox(height: 14),

                        // Card Cấu Hình Mặc Định
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border.withOpacity(0.8)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CẤU HÌNH GIỌNG ĐỌC & NHỊP ĐIỆU',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 10),

                              // Giọng đọc mặc định
                              const Text('Giọng đọc mặc định (Default Voice):', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              _buildVoiceDropdown(context, state, controller),

                              const SizedBox(height: 12),

                              // Tốc độ đọc (Speed) - ĐẶC BIỆT LƯU Ý THEO YÊU CẦU NGƯỜI DÙNG
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.speed, size: 14, color: AppColors.primary),
                                      SizedBox(width: 4),
                                      Text('Tốc độ đọc (Speed):', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                  Text(
                                    '${state.defaultSpeed.toStringAsFixed(2)}x (~${(140 * state.defaultSpeed).round()} từ/phút)',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: state.defaultSpeed.clamp(0.75, 1.75),
                                  min: 0.75,
                                  max: 1.75,
                                  divisions: 20,
                                  activeColor: AppColors.primary,
                                  inactiveColor: AppColors.border,
                                  onChanged: (val) => controller.setDefaultSpeed(val),
                                ),
                              ),

                              const SizedBox(height: 4),

                              // Khoảng lặng ngắt câu (Sentence Pause)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.pause_circle_outline, size: 14, color: AppColors.info),
                                      SizedBox(width: 4),
                                      Text('Nghỉ giữa các câu (Pause):', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                  Text(
                                    '${state.pauseSec.toStringAsFixed(2)}s',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.info),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: state.pauseSec.clamp(0.1, 1.0),
                                  min: 0.1,
                                  max: 1.0,
                                  divisions: 18,
                                  activeColor: AppColors.info,
                                  inactiveColor: AppColors.border,
                                  onChanged: (val) => controller.setPauseSec(val),
                                ),
                              ),

                              const SizedBox(height: 4),

                              // Cao độ giọng đọc (Pitch)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.graphic_eq, size: 14, color: Color(0xFF10B981)),
                                      SizedBox(width: 4),
                                      Text('Cao độ (Pitch):', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                  Text(
                                    '${state.defaultPitch > 0 ? "+" : ""}${state.defaultPitch}Hz',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                ),
                                child: Slider(
                                  value: state.defaultPitch.toDouble().clamp(-20.0, 20.0),
                                  min: -20,
                                  max: 20,
                                  divisions: 40,
                                  activeColor: const Color(0xFF10B981),
                                  inactiveColor: AppColors.border,
                                  onChanged: (val) => controller.setDefaultPitch(val.round()),
                                ),
                              ),

                              const SizedBox(height: 10),
                              const Divider(color: AppColors.border, height: 1),
                              const SizedBox(height: 10),

                              // Switch Khóa Timeline [start - end]
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.lock_clock_outlined, size: 15, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Khóa Timeline [start - end]',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Giữ đúng mốc thời gian, tự động tăng tốc câu dài (không trần) và nghỉ chờ câu tiếp.',
                                          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted.withOpacity(0.9), height: 1.3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: state.isTimelineLocked,
                                    activeColor: const Color(0xFFF59E0B),
                                    onChanged: (val) => controller.toggleLockTimeline(val),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Nút Hành Động Phân Tách
                        AppButton(
                          label: '⚡ Phân Tách Kịch Bản Thành Câu',
                          icon: Icons.splitscreen,
                          variant: AppButtonVariant.primary,
                          height: 38,
                          fontSize: 12.5,
                          isLoading: state.isSplitting,
                          onPressed: () => controller.splitScript(),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── PANEL PHẢI: DANH SÁCH PHÂN ĐOẠN (EXPANDED) ──────────────
                Expanded(
                  child: state.segments.isEmpty
                      ? _buildEmptyState(context, controller)
                      : Column(
                          children: [
                            // Header Danh Sách
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withOpacity(0.5),
                                border: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '2. DANH SÁCH PHÂN ĐOẠN (${state.segments.length} CÂU)',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'Nhấn biểu tượng Play trên từng thẻ để nghe thử tức thì',
                                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),

                            // Danh sách Card Cuộn
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: state.segments.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (ctx, index) {
                                  final seg = state.segments[index];
                                  return _buildSegmentCard(ctx, seg, state, controller);
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // ── 3. BOTTOM PERSISTENT ACTION BAR ──────────────────────────
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Row(
              children: [
                // Trạng thái hệ thống
                Icon(
                  state.isRenderingFull
                      ? Icons.hourglass_top
                      : (state.isPlayingFull ? Icons.volume_up : Icons.info_outline),
                  size: 16,
                  color: state.isRenderingFull ? AppColors.statusProcessing : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.statusMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),

                if (state.totalDuration > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 0.8),
                    ),
                    child: Text(
                      '⏱️ Tổng: ${state.totalDuration.toStringAsFixed(1)}s (~${(state.totalDuration / 60).toStringAsFixed(1)}p)',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Action: Nghe toàn bài
                AppButton(
                  label: state.isPlayingFull ? 'Dừng Phát' : 'Phát Toàn Bài',
                  icon: state.isPlayingFull ? Icons.stop : Icons.play_arrow,
                  variant: AppButtonVariant.secondary,
                  height: 32,
                  fontSize: 11.5,
                  onPressed: state.segments.isEmpty ? null : () => controller.togglePlayFullAudio(),
                ),
                const SizedBox(width: 8),

                // Action: Xuất MP3 & Phụ Đề
                AppButton(
                  label: 'Xuất MP3 & Phụ Đề',
                  icon: Icons.file_download_outlined,
                  variant: AppButtonVariant.outlined,
                  height: 32,
                  fontSize: 11.5,
                  isLoading: state.isRenderingFull,
                  onPressed: state.segments.isEmpty
                      ? null
                      : () async {
                          final selectedDir = await FilePicker.platform.getDirectoryPath();
                          if (selectedDir != null) {
                            final timestamp = DateTime.now().millisecondsSinceEpoch;
                            final outAudio = p.join(selectedDir, 'tts_audio_$timestamp.mp3');
                            final outSrt = p.join(selectedDir, 'tts_audio_$timestamp.srt');
                            final ok = await controller.renderFull(
                              customAudioPath: outAudio,
                              customSrtPath: outSrt,
                            );
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✅ Đã xuất audio và phụ đề thành công tới:\n$outAudio'),
                                  backgroundColor: AppColors.statusCompleted,
                                ),
                              );
                            }
                          }
                        },
                ),
                const SizedBox(width: 8),

                // Action: Đưa vào Video Studio
                AppButton.primary(
                  label: 'Đưa Vào Ghép & Cắt Studio',
                  icon: Icons.movie_edit,
                  height: 32,
                  fontSize: 11.5,
                  isLoading: state.isRenderingFull,
                  onPressed: state.segments.isEmpty
                      ? null
                      : () async {
                          final destPath = await controller.exportToProjectWorkspace();
                          if (destPath != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Đã chuyển file âm thanh và phụ đề vào thư mục src của dự án!'),
                                backgroundColor: AppColors.statusCompleted,
                              ),
                            );
                            if (widget.onNavigateTab != null) {
                              widget.onNavigateTab!(1); // Chuyển sang Tab Ghép & Cắt Studio (index 1)
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceDropdown(BuildContext context, TtsStudioState state, TtsStudioController controller) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: state.defaultVoice,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                items: state.availableVoices.map((v) {
                  return DropdownMenuItem<String>(
                    value: v.id,
                    child: Row(
                      children: [
                        Text(v.flagEmoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${v.name} (${v.genderLabel})',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: v.lang == 'vi' ? AppColors.primary.withOpacity(0.15) : AppColors.info.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            v.region,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: v.lang == 'vi' ? AppColors.primary : AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) controller.setDefaultVoice(val);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: 'Nghe thử mẫu giọng này',
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => controller.previewVoiceSample(state.defaultVoice),
            child: Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: const Icon(Icons.volume_up, size: 18, color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, TtsStudioController controller) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.record_voice_over_outlined, size: 56, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 14),
          const Text(
            'Chưa có phân đoạn câu nào',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nhập kịch bản ở khung bên trái và bấm "Phân Tách Kịch Bản",\nhoặc dùng các nút thử nhanh kịch bản mẫu dưới đây.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Thử Kịch Bản Tiếng Anh (US/UK)',
                icon: Icons.language,
                variant: AppButtonVariant.primary,
                height: 32,
                onPressed: () {
                  controller.loadSampleEnglishScript();
                  controller.splitScript();
                },
              ),
              const SizedBox(width: 10),
              AppButton(
                label: 'Thử Kịch Bản Tiếng Việt',
                icon: Icons.flag,
                variant: AppButtonVariant.secondary,
                height: 32,
                onPressed: () {
                  controller.loadSampleVietnameseScript();
                  controller.splitScript();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(
    BuildContext context,
    TtsSegmentItem seg,
    TtsStudioState state,
    TtsStudioController controller,
  ) {
    final isPlaying = state.currentlyPlayingSegmentId == seg.id;
    final effectiveVoice = seg.voice ?? state.defaultVoice;
    final baseSpeed = seg.speed ?? state.defaultSpeed;

    final slotDur = (seg.endSec > seg.startSec) ? (seg.endSec - seg.startSec) : 0.0;
    final words = seg.text.trim().isEmpty ? 0 : seg.text.trim().split(RegExp(r'\s+')).length;
    final estNatDur = words > 0 ? (words / (140.0 / 60.0)) : 0.5;
    final estDurAtBase = estNatDur / baseSpeed;
    final isBoostedCalc = state.isTimelineLocked && slotDur > 0 && estDurAtBase > (slotDur + 0.05);
    final reqSpeed = (slotDur > 0 && isBoostedCalc) ? (estNatDur / slotDur) : baseSpeed;
    final effectiveSpeed = seg.effectiveSpeed ?? (isBoostedCalc ? reqSpeed : baseSpeed);
    final isBoosted = seg.isBoosted || isBoostedCalc;

    final hasWaitGap = state.isTimelineLocked && seg.duration > 0 && slotDur > seg.duration + 0.05;
    final waitGapSec = hasWaitGap ? (slotDur - seg.duration) : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPlaying ? AppColors.primary.withOpacity(0.06) : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPlaying ? AppColors.primary : AppColors.border.withOpacity(0.8),
          width: isPlaying ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Thẻ
          Row(
            children: [
              // Badge Thứ tự
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${seg.id.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 8),

              Text(
                '$words từ',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),

              if (seg.startSec > 0 || seg.endSec > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: state.isTimelineLocked
                        ? const Color(0xFFF59E0B).withOpacity(0.14)
                        : AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                    border: state.isTimelineLocked
                        ? Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4), width: 0.8)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.isTimelineLocked) ...[
                        const Icon(Icons.lock_clock_outlined, size: 10, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        '${seg.startSec.toStringAsFixed(1)}s - ${seg.endSec.toStringAsFixed(1)}s',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: state.isTimelineLocked ? const Color(0xFFF59E0B) : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (isBoosted) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, size: 10, color: Color(0xFFEF4444)),
                      const SizedBox(width: 2),
                      Text(
                        '${effectiveSpeed.toStringAsFixed(2)}x (Tăng tốc)',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                ),
              ],

              if (seg.duration > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${seg.duration.toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  ),
                ),
              ],

              if (hasWaitGap) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '⏸️ Nghỉ ${waitGapSec.toStringAsFixed(1)}s',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.info),
                  ),
                ),
              ],

              const Spacer(),

              // Tùy chọn giọng riêng (Phân vai thoại)
              PopupMenuButton<String>(
                tooltip: 'Đổi giọng riêng cho câu này (Phân vai)',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                color: AppColors.surface,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: seg.voice != null ? AppColors.primary.withOpacity(0.15) : AppColors.surfaceLight.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: seg.voice != null ? AppColors.primary : AppColors.border,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic, size: 12, color: seg.voice != null ? AppColors.primary : AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        seg.voice != null
                            ? state.availableVoices.firstWhere((v) => v.id == seg.voice, orElse: () => state.availableVoices.first).name
                            : 'Mặc định (${state.availableVoices.firstWhere((v) => v.id == effectiveVoice, orElse: () => state.availableVoices.first).name})',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: seg.voice != null ? AppColors.primary : AppColors.textSecondary),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.textMuted),
                    ],
                  ),
                ),
                onSelected: (val) {
                  controller.updateSegmentVoice(seg.id, val == 'default' ? null : val);
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('Kế thừa giọng mặc định', style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary)),
                  ),
                  const PopupMenuDivider(),
                  ...state.availableVoices.map((v) => PopupMenuItem(
                        value: v.id,
                        child: Text('${v.flagEmoji} ${v.name} (${v.genderLabel})', style: const TextStyle(fontSize: 11.5)),
                      )),
                ],
              ),

              const SizedBox(width: 6),

              // Nút xóa câu
              IconButton(
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Xóa câu này',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                color: AppColors.textMuted,
                onPressed: () => controller.deleteSegment(seg.id),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Nội dung text có thể chỉnh sửa
          TextFormField(
            initialValue: seg.text,
            maxLines: null,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.4),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surfaceLight.withOpacity(0.3),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: AppColors.border.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (val) => controller.updateSegmentText(seg.id, val),
          ),

          const SizedBox(height: 8),

          // Footer Thao tác: Nghe thử + Tốc độ riêng + Thêm câu bên dưới
          Row(
            children: [
              // Nút Phát Thử
              AppButton(
                label: isPlaying ? 'Dừng' : 'Nghe Thử',
                icon: isPlaying ? Icons.stop : Icons.play_arrow,
                variant: isPlaying ? AppButtonVariant.primary : AppButtonVariant.secondary,
                height: 26,
                fontSize: 10.5,
                isLoading: seg.isSynthesizing,
                onPressed: () => controller.previewSegment(seg.id),
              ),

              const SizedBox(width: 8),

              // Chip hiển thị tốc độ hiệu dụng
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Tốc độ: ${effectiveSpeed.toStringAsFixed(2)}x',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                ),
              ),

              const Spacer(),

              // Nút thêm câu phía dưới
              TextButton.icon(
                icon: const Icon(Icons.add, size: 13),
                label: const Text('Thêm câu dưới', style: TextStyle(fontSize: 10.5)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.textMuted,
                ),
                onPressed: () => controller.addSegmentBelow(seg.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
