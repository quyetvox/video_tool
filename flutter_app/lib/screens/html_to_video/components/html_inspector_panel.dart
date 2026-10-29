import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/settings_section_card.dart';
import '../models/html_to_video_models.dart';

class HtmlInspectorPanel extends StatefulWidget {
  final TextEditingController htmlPathCtrl, outputPathCtrl, selectorCtrl, durationCtrl, widthCtrl, heightCtrl;
  final TextEditingController scriptPathCtrl, audioPathCtrl, assPathCtrl, subOutlineWidthCtrl, subMarginVCtrl, secondaryFontScaleCtrl;
  final String mode, selectedResPreset, numWorkers, codec, voice, secondaryVoice, secondaryPosition, subFont, subColorHex, subOutlineHex;
  final ValueChanged<String> onModeChanged, onResPresetChanged, onNumWorkersChanged, onCodecChanged, onVoiceChanged, onSecondaryVoiceChanged, onSecondaryPositionChanged, onSubFontChanged, onSubColorHexChanged, onSubOutlineHexChanged;
  final VoidCallback onCustomDimensionChanged, onPickHtml, onPickOutput, onPickScript, onClearScript, onPickAudio, onClearAudio, onPickAss, onClearAss;
  final VoidCallback? onOpenTtsStudio;
  final double fps, speechSpeed;
  final ValueChanged<double> onFpsChanged, onSpeechSpeedChanged;
  final int crf, subFontSize;
  final ValueChanged<int> onCrfChanged, onSubFontSizeChanged;
  final bool lockTimeline, burnSubtitles, enableSecondarySub;
  final ValueChanged<bool> onLockTimelineChanged, onBurnSubtitlesChanged, onEnableSecondarySubChanged;
  final HtmlAudioSourceMode audioSourceMode;
  final ValueChanged<HtmlAudioSourceMode> onAudioSourceModeChanged;

  const HtmlInspectorPanel({
    super.key,
    required this.htmlPathCtrl, required this.outputPathCtrl, required this.selectorCtrl,
    required this.durationCtrl, required this.widthCtrl, required this.heightCtrl,
    required this.scriptPathCtrl, required this.audioPathCtrl, required this.assPathCtrl,
    required this.subOutlineWidthCtrl, required this.subMarginVCtrl, required this.secondaryFontScaleCtrl,
    required this.mode, required this.onModeChanged, required this.selectedResPreset, required this.onResPresetChanged,
    required this.onCustomDimensionChanged, required this.fps, required this.onFpsChanged,
    required this.numWorkers, required this.onNumWorkersChanged, required this.codec, required this.onCodecChanged,
    required this.crf, required this.onCrfChanged, required this.lockTimeline, required this.onLockTimelineChanged,
    required this.speechSpeed, required this.onSpeechSpeedChanged, required this.audioSourceMode, required this.onAudioSourceModeChanged,
    required this.voice, required this.onVoiceChanged, required this.secondaryVoice, required this.onSecondaryVoiceChanged,
    required this.burnSubtitles, required this.onBurnSubtitlesChanged,
    required this.enableSecondarySub, required this.onEnableSecondarySubChanged, required this.secondaryPosition, required this.onSecondaryPositionChanged,
    required this.subFont, required this.onSubFontChanged, required this.subFontSize, required this.onSubFontSizeChanged,
    required this.subColorHex, required this.onSubColorHexChanged, required this.subOutlineHex, required this.onSubOutlineHexChanged,
    required this.onPickHtml, required this.onPickOutput, required this.onPickScript, required this.onClearScript,
    required this.onPickAudio, required this.onClearAudio, required this.onPickAss, required this.onClearAss,
    this.onOpenTtsStudio,
  });

  @override
  State<HtmlInspectorPanel> createState() => _HtmlInspectorPanelState();
}

class _HtmlInspectorPanelState extends State<HtmlInspectorPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(right: BorderSide(color: c.border))),
      child: Column(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(color: c.surfaceDark, border: Border(bottom: BorderSide(color: c.border))),
            child: TabBar(
              controller: _tabController,
              indicatorColor: c.primary, indicatorWeight: 2, labelColor: c.primary, unselectedLabelColor: c.textSecondary,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              isScrollable: true, tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: '🌐 HTML & Render'),
                Tab(text: '🎙️ Thuyết Minh & Audio'),
                Tab(text: '📐 Phụ Đề & Style'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildHtmlRenderTab(c), _buildAudioNarrationTab(c), _buildSubtitleStyleTab(c)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlRenderTab(AppFallbackPalette c) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSectionCard(
          title: 'Tệp HTML Nguồn & Đích MP4', icon: Icons.html_rounded,
          subtitle: 'Chọn tệp HTML hoạt họa và đường dẫn lưu video MP4',
          children: [
            AppInputGroup(
              label: 'File HTML nguồn (.html)',
              field: AppTextField(controller: widget.htmlPathCtrl, hint: 'Đường dẫn tới file .html...', isMonospace: true),
              button: AppButton.outlined(icon: Icons.folder_open_rounded, label: 'Chọn', height: 34, onPressed: widget.onPickHtml),
            ),
            const SizedBox(height: 10),
            AppInputGroup(
              label: 'File Video đầu ra (.mp4)',
              field: AppTextField(controller: widget.outputPathCtrl, hint: 'Đường dẫn lưu file .mp4...', isMonospace: true),
              button: AppButton.outlined(icon: Icons.save_as_rounded, label: 'Lưu tại', height: 34, onPressed: widget.onPickOutput),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SettingsSectionCard(
          title: 'Khung Hình & Đa Luồng Scene Split', icon: Icons.tune_rounded,
          subtitle: 'Tự động chia nhỏ Scene và ghép nối Zero-Reencode (-c:v copy)',
          children: [
            Row(
              children: [
                Expanded(
                  child: AppDropdown<String>(
                    label: 'Chế độ Quét HTML', value: widget.mode,
                    items: const [
                      DropdownMenuItem(value: 'fullpage', child: Text('Toàn bộ trang (Full Page)')),
                      DropdownMenuItem(value: 'selector', child: Text('Thẻ phần tử (CSS Selector)')),
                    ],
                    onChanged: (v) => v != null ? widget.onModeChanged(v) : null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: AppTextField(label: 'Thời lượng (s)', controller: widget.durationCtrl, keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: AppDropdown<double>(
                    label: 'Tốc độ FPS', value: widget.fps,
                    items: const [24.0, 25.0, 30.0, 60.0].map((f) => DropdownMenuItem(value: f, child: Text('${f.toInt()} FPS'))).toList(),
                    onChanged: (v) => v != null ? widget.onFpsChanged(v) : null,
                  ),
                ),
              ],
            ),
            if (widget.mode == 'selector') ...[
              const SizedBox(height: 10),
              AppTextField(label: 'CSS Selector mục tiêu (VD: #stage, .card)', controller: widget.selectorCtrl, hint: '#stage', isMonospace: true),
            ],
            const SizedBox(height: 10),
            AppDropdown<String>(
              label: 'Khung tỷ lệ chuẩn (Resolution Preset)', value: widget.selectedResPreset,
              items: [
                ...kHtmlResolutionPresets.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))),
                if (!kHtmlResolutionPresets.containsKey(widget.selectedResPreset))
                  DropdownMenuItem(value: widget.selectedResPreset, child: Text(widget.selectedResPreset)),
              ],
              onChanged: (v) => v != null ? widget.onResPresetChanged(v) : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: AppTextField(label: 'Chiều rộng (Width px)', controller: widget.widthCtrl, keyboardType: TextInputType.number, onChanged: (_) => widget.onCustomDimensionChanged())),
                const SizedBox(width: 8),
                Expanded(child: AppTextField(label: 'Chiều cao (Height px)', controller: widget.heightCtrl, keyboardType: TextInputType.number, onChanged: (_) => widget.onCustomDimensionChanged())),
              ],
            ),
            const SizedBox(height: 10),
            AppDropdown<String>(
              label: 'Số luồng xử lý đa nhân (Multi-Process Scene Workers)', value: widget.numWorkers,
              items: kHtmlWorkerPresets.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key))).toList(),
              onChanged: (v) => v != null ? widget.onNumWorkersChanged(v) : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, dense: true,
              title: Row(
                children: [
                  Flexible(child: Text('Khóa Timeline (Timeline Lock)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.textPrimary, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 6),
                  Icon(Icons.lock_clock_outlined, size: 14, color: c.primary),
                ],
              ),
              subtitle: Text(
                widget.lockTimeline
                    ? 'Bật: Khóa đúng mốc slot [start - end], tự động tăng tốc nếu chữ dài, giữ sàn ${widget.speechSpeed.toStringAsFixed(2)}x'
                    : 'Tắt (Auto): Audio làm chuẩn thời gian (Master), animation tự co giãn khớp 100% giọng đọc',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
              value: widget.lockTimeline, activeColor: c.primary, onChanged: widget.onLockTimelineChanged,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: AppDropdown<String>(
                    label: 'Chuẩn nén Video Codec', value: widget.codec,
                    items: const [
                      DropdownMenuItem(value: 'libx264', child: Text('H.264 (MP4 Phổ biến)')),
                      DropdownMenuItem(value: 'libx265', child: Text('H.265 / HEVC (Nhẹ dung lượng)')),
                    ],
                    onChanged: (v) => v != null ? widget.onCodecChanged(v) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppDropdown<int>(
                    label: 'Chất lượng nén (CRF)', value: widget.crf,
                    items: const [
                      DropdownMenuItem(value: 14, child: Text('CRF 14 (Lossless)')),
                      DropdownMenuItem(value: 18, child: Text('CRF 18 (Sắc nét - Khuyên dùng)')),
                      DropdownMenuItem(value: 23, child: Text('CRF 23 (Chuẩn nhẹ)')),
                    ],
                    onChanged: (v) => v != null ? widget.onCrfChanged(v) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioNarrationTab(AppFallbackPalette c) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
          child: Row(
            children: [
              Expanded(
                child: AppSegmentButton(
                  icon: Icons.auto_awesome_rounded, label: 'Kịch bản TTS',
                  isSelected: widget.audioSourceMode == HtmlAudioSourceMode.autoScript,
                  onTap: () => widget.onAudioSourceModeChanged(HtmlAudioSourceMode.autoScript),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: AppSegmentButton(
                  icon: Icons.library_music_rounded, label: 'Audio / Sub',
                  isSelected: widget.audioSourceMode == HtmlAudioSourceMode.manualAudio,
                  onTap: () => widget.onAudioSourceModeChanged(HtmlAudioSourceMode.manualAudio),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: AppSegmentButton(
                  icon: Icons.volume_off_rounded, label: 'Chỉ HTML',
                  isSelected: widget.audioSourceMode == HtmlAudioSourceMode.videoOnly,
                  onTap: () => widget.onAudioSourceModeChanged(HtmlAudioSourceMode.videoOnly),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (widget.audioSourceMode == HtmlAudioSourceMode.autoScript)
          SettingsSectionCard(
            title: 'Thuyết Minh Tự Động Từ Kịch Bản (.txt / .md)', icon: Icons.record_voice_over_rounded,
            subtitle: 'Tự động sinh giọng đọc AI và căn khớp tốc độ HTML theo từng mốc thời gian',
            trailing: widget.onOpenTtsStudio != null
                ? AppButton.ghost(icon: Icons.open_in_new_rounded, label: 'Mở TTS Studio', height: 26, onPressed: widget.onOpenTtsStudio)
                : null,
            children: [
              AppInputGroup(
                label: 'File Kịch bản thuyết minh (.txt, .md)',
                field: AppTextField(
                  controller: widget.scriptPathCtrl, hint: 'Chọn file kịch bản có sẵn hoặc gửi từ TTS Studio...', isMonospace: true,
                  suffixIcon: widget.scriptPathCtrl.text.isNotEmpty
                      ? AppIconButton(icon: Icons.clear_rounded, tooltip: 'Xóa kịch bản', onPressed: widget.onClearScript)
                      : null,
                ),
                button: AppButton.outlined(icon: Icons.description_outlined, label: 'Chọn', height: 34, onPressed: widget.onPickScript),
              ),
              const SizedBox(height: 10),
              AppDropdown<String>(
                label: 'Giọng đọc chính (Primary Voice)', value: widget.voice,
                items: kHtmlVoicePresets.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key))).toList(),
                onChanged: (v) => v != null ? widget.onVoiceChanged(v) : null,
              ),
              const SizedBox(height: 10),
              AppDropdown<String>(
                label: 'Giọng phụ (Hội thoại / Secondary)', value: widget.secondaryVoice,
                items: kHtmlSecondaryVoicePresets.entries.map((e) => DropdownMenuItem(value: e.value, child: Text(e.key))).toList(),
                onChanged: (v) => v != null ? widget.onSecondaryVoiceChanged(v) : null,
              ),
              const SizedBox(height: 10),
              AppSliderRow(
                label: 'Tốc độ đọc mặc định (Speed)',
                value: widget.speechSpeed,
                min: 0.5,
                max: 2.0,
                formatValue: (v) => '${v.toStringAsFixed(2)}x',
                onChanged: widget.onSpeechSpeedChanged,
              ),
            ],
          )
        else if (widget.audioSourceMode == HtmlAudioSourceMode.manualAudio)
          SettingsSectionCard(
            title: 'Ghép File Audio & Phụ Đề Có Sẵn', icon: Icons.audio_file_rounded,
            subtitle: 'Dùng file Master Audio từ Tạo Giọng Đọc hoặc file thu âm ngoài',
            children: [
              AppInputGroup(
                label: 'File Âm thanh (.mp3, .wav, .m4a)',
                field: AppTextField(
                  controller: widget.audioPathCtrl, hint: 'Chọn file âm thanh để ghép...', isMonospace: true,
                  suffixIcon: widget.audioPathCtrl.text.isNotEmpty
                      ? AppIconButton(icon: Icons.clear_rounded, tooltip: 'Xóa Audio', onPressed: widget.onClearAudio)
                      : null,
                ),
                button: AppButton.outlined(icon: Icons.audiotrack_rounded, label: 'Chọn', height: 34, onPressed: widget.onPickAudio),
              ),
              const SizedBox(height: 10),
              AppInputGroup(
                label: 'File Phụ đề (.ass, .srt) — Tùy chọn',
                field: AppTextField(
                  controller: widget.assPathCtrl, hint: 'Chọn file phụ đề để đốt cứng vào video...', isMonospace: true,
                  suffixIcon: widget.assPathCtrl.text.isNotEmpty
                      ? AppIconButton(icon: Icons.clear_rounded, tooltip: 'Xóa Phụ đề', onPressed: widget.onClearAss)
                      : null,
                ),
                button: AppButton.outlined(icon: Icons.subtitles_outlined, label: 'Chọn', height: 34, onPressed: widget.onPickAss),
              ),
            ],
          )
        else
          SettingsSectionCard(
            title: 'Chế Độ Chỉ Xuất Hình Ảnh HTML', icon: Icons.videocam_outlined,
            subtitle: 'Bỏ qua bước tạo giọng đọc và ghép âm thanh',
            children: [
              Text(
                'Video MP4 xuất ra sẽ chỉ chứa hoạt họa HTML thuần túy theo đúng thời lượng đã cài đặt ở tab "HTML & Render".',
                style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 1.4),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSubtitleStyleTab(AppFallbackPalette c) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSectionCard(
          title: 'Hiển Thị Phụ Đề & Song Ngữ', icon: Icons.subtitles_rounded,
          subtitle: 'Cấu hình đốt phụ đề cứng (Hardsub) và dòng phụ đề phụ',
          children: [
            AppToggleRow(
              label: 'Đốt phụ đề cứng vào video (Burn-in Subtitles)',
              subtitle: 'Tự động gắn phụ đề vào luồng hình ảnh khi kết xuất',
              value: widget.burnSubtitles, onChanged: widget.onBurnSubtitlesChanged,
            ),
            Divider(color: c.border, height: 14),
            AppToggleRow(
              label: 'Bật phụ đề phụ song ngữ (Secondary Subtitle)',
              subtitle: 'Hiển thị dòng phụ đề thứ 2 khi kịch bản có 2 ngôn ngữ',
              value: widget.enableSecondarySub, onChanged: widget.onEnableSecondarySubChanged,
            ),
            if (widget.enableSecondarySub) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<String>(
                      label: 'Vị trí dòng phụ', value: widget.secondaryPosition,
                      items: const [
                        DropdownMenuItem(value: 'above', child: Text('Phía trên sub chính')),
                        DropdownMenuItem(value: 'below', child: Text('Phía dưới sub chính')),
                      ],
                      onChanged: (v) => v != null ? widget.onSecondaryPositionChanged(v) : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: AppTextField(label: 'Tỷ lệ cỡ chữ phụ', controller: widget.secondaryFontScaleCtrl, keyboardType: TextInputType.number)),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SettingsSectionCard(
          title: 'Kiểu Chữ, Viền & Căn Lề Phụ Đề', icon: Icons.text_fields_rounded,
          subtitle: 'Áp dụng cho cả phụ đề kịch bản tự động và phụ đề rời',
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: AppDropdown<String>(
                    label: 'Font chữ', value: widget.subFont,
                    items: kHtmlFontPresets.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (v) => v != null ? widget.onSubFontChanged(v) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppDropdown<int>(
                    label: 'Cỡ chữ (px)', value: widget.subFontSize,
                    items: const [28, 32, 36, 40, 44, 48, 52, 56, 64].map((s) => DropdownMenuItem(value: s, child: Text('$s px'))).toList(),
                    onChanged: (v) => v != null ? widget.onSubFontSizeChanged(v) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: AppTextField(label: 'Độ dày viền (px)', controller: widget.subOutlineWidthCtrl, keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: AppTextField(label: 'Lề dưới (Margin V)', controller: widget.subMarginVCtrl, keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppDropdown<String>(
                    label: 'Màu chữ chính', value: widget.subColorHex,
                    items: const [
                      DropdownMenuItem(value: '#FFFFFF', child: Text('⬜ Trắng (#FFFFFF)')),
                      DropdownMenuItem(value: '#FFD700', child: Text('🟨 Vàng Gold (#FFD700)')),
                      DropdownMenuItem(value: '#00FFFF', child: Text('🟦 Xanh Cyan (#00FFFF)')),
                      DropdownMenuItem(value: '#38BDF8', child: Text('🔷 Xanh Sky (#38BDF8)')),
                    ],
                    onChanged: (v) => v != null ? widget.onSubColorHexChanged(v) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppDropdown<String>(
                    label: 'Màu viền chữ', value: widget.subOutlineHex,
                    items: const [
                      DropdownMenuItem(value: '#000000', child: Text('⬛ Đen (#000000)')),
                      DropdownMenuItem(value: '#0F172A', child: Text('🌑 Xanh Đen (#0F172A)')),
                      DropdownMenuItem(value: '#1E293B', child: Text('🌚 Xám Đậm (#1E293B)')),
                    ],
                    onChanged: (v) => v != null ? widget.onSubOutlineHexChanged(v) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

