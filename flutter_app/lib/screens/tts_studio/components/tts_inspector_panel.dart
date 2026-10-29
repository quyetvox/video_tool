import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../widgets/app_kit.dart';
import '../../../widgets/settings_section_card.dart';
import '../controllers/tts_studio_controller.dart';
import '../models/tts_models.dart';

class TtsInspectorPanel extends StatefulWidget {
  final TtsStudioState state;
  final TtsStudioController controller;
  final TextEditingController scriptCtrl;
  final VoidCallback onPickTextFile;
  final VoidCallback onClearScript;
  final VoidCallback onSplitScript;

  const TtsInspectorPanel({
    super.key,
    required this.state,
    required this.controller,
    required this.scriptCtrl,
    required this.onPickTextFile,
    required this.onClearScript,
    required this.onSplitScript,
  });

  @override
  State<TtsInspectorPanel> createState() => _TtsInspectorPanelState();
}

class _TtsInspectorPanelState extends State<TtsInspectorPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _langFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        children: [
          // ── SUBTAB HEADER (38PX - MATCHING VIDEO EDITOR INSPECTOR) ──
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
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: '📖 Kịch Bản Nguồn'),
                Tab(text: '🎙️ Giọng Đọc & Nhịp Điệu'),
              ],
            ),
          ),

          // ── SUBTAB VIEWS ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScriptSourceTab(c),
                _buildVoiceAndRhythmTab(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── TAB 1: KỊCH BẢN NGUỒN & TÁCH CÂU (1 NÚT PHÂN TÁCH DUY NHẤT) ───────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildScriptSourceTab(AppFallbackPalette c) {
    final state = widget.state;
    final ctrl = widget.controller;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSectionCard(
          title: 'Nhập Hoặc Nạp Kịch Bản Thuyết Minh',
          icon: Icons.description_outlined,
          subtitle: 'Hỗ trợ file .txt, .md (có mốc thời gian [00:00 -> 00:05])',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton.outlined(
                icon: Icons.upload_file_rounded,
                label: 'Nhập File (.txt/.md)',
                height: 26,
                onPressed: widget.onPickTextFile,
              ),
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Xóa trắng kịch bản',
                onPressed: widget.onClearScript,
              ),
            ],
          ),
          children: [
            Row(
              children: [
                Text(
                  'Mẫu thử nhanh:',
                  style: TextStyle(fontSize: 10.5, color: c.textSecondary),
                ),
                const SizedBox(width: 6),
                AppButton.ghost(
                  label: '🇻🇳 Mẫu Tiếng Việt',
                  height: 24,
                  fontSize: 10,
                  onPressed: () async {
                    await ctrl.loadSampleVietnameseScript();
                    widget.scriptCtrl.text = refReadRawScript();
                  },
                ),
                const SizedBox(width: 4),
                AppButton.ghost(
                  label: '🇺🇸 Mẫu Tiếng Anh',
                  height: 24,
                  fontSize: 10,
                  onPressed: () async {
                    await ctrl.loadSampleEnglishScript();
                    widget.scriptCtrl.text = refReadRawScript();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: widget.scriptCtrl,
              maxLines: 12,
              height: 230,
              hint:
                  'Dán hoặc gõ kịch bản thuyết minh vào đây...\nHệ thống sẽ tự động nhận diện dấu câu và mốc thời gian để chia thành các câu thoại hoàn chỉnh.',
              onChanged: ctrl.setRawScript,
            ),
            const SizedBox(height: 12),
            AppButton.primary(
              icon: Icons.bolt_rounded,
              label: state.isSplitting
                  ? 'Đang phân tách câu...'
                  : '⚡ Phân Tách Kịch Bản Thành Câu',
              isLoading: state.isSplitting,
              width: double.infinity,
              height: 34,
              onPressed: state.isSplitting ? null : widget.onSplitScript,
            ),
          ],
        ),
      ],
    );
  }

  String refReadRawScript() => widget.state.rawScript;

  // ═══════════════════════════════════════════════════════════════════════════
  // ── TAB 2: GIỌNG ĐỌC & NHỊP ĐIỆU ───────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildVoiceAndRhythmTab(AppFallbackPalette c) {
    final state = widget.state;
    final ctrl = widget.controller;
    final filteredVoices = state.availableVoices.where((v) {
      if (_langFilter == 'all') return true;
      return v.lang == _langFilter;
    }).toList();

    final effectiveVoices = filteredVoices.any((v) => v.id == state.defaultVoice)
        ? filteredVoices
        : state.availableVoices;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SettingsSectionCard(
          title: 'Giọng Đọc Mặc Định & Nghe Thử Mẫu',
          icon: Icons.record_voice_over_rounded,
          subtitle: 'Chọn giọng đọc chính cho toàn bộ kịch bản',
          children: [
            Row(
              children: [
                AppFilterChip(
                  label: 'Tất cả (${state.availableVoices.length})',
                  isSelected: _langFilter == 'all',
                  onTap: () => setState(() => _langFilter = 'all'),
                ),
                const SizedBox(width: 6),
                AppFilterChip(
                  label: '🇻🇳 Tiếng Việt',
                  isSelected: _langFilter == 'vi',
                  onTap: () => setState(() => _langFilter = 'vi'),
                ),
                const SizedBox(width: 6),
                AppFilterChip(
                  label: '🇺🇸🇬🇧 Tiếng Anh',
                  isSelected: _langFilter == 'en',
                  onTap: () => setState(() => _langFilter = 'en'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppInputGroup(
              label: 'Giọng đọc mặc định (Default Voice)',
              field: AppDropdown<String>(
                value: effectiveVoices.any((v) => v.id == state.defaultVoice)
                    ? state.defaultVoice
                    : effectiveVoices.first.id,
                items: effectiveVoices
                    .map(
                      (v) => DropdownMenuItem<String>(
                        value: v.id,
                        child: Text(
                          '${v.flagEmoji} ${v.name} (${v.genderLabel}) — ${v.desc}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) ctrl.setDefaultVoice(v);
                },
              ),
              button: AppButton.outlined(
                icon: Icons.volume_up_rounded,
                label: 'Nghe mẫu',
                height: 34,
                onPressed: () => ctrl.previewVoiceSample(state.defaultVoice),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SettingsSectionCard(
          title: 'Tốc Độ, Cao Độ & Nhịp Nghỉ',
          icon: Icons.speed_rounded,
          subtitle: 'Điều chỉnh nhịp đọc tự nhiên và khóa mốc thời gian',
          children: [
            AppSliderRow(
              label: 'Tốc độ đọc mặc định (Speed)',
              value: state.defaultSpeed,
              min: 0.5,
              max: 2.0,
              formatValue: (v) => '${v.toStringAsFixed(2)}x',
              onChanged: ctrl.setDefaultSpeed,
            ),
            const SizedBox(height: 6),
            AppSliderRow(
              label: 'Cao độ giọng (Pitch)',
              value: state.defaultPitch.toDouble(),
              min: -20.0,
              max: 20.0,
              formatValue: (v) => '${v.round() >= 0 ? "+" : ""}${v.round()} Hz',
              onChanged: (v) => ctrl.setDefaultPitch(v.round()),
            ),
            const SizedBox(height: 6),
            AppSliderRow(
              label: 'Khoảng nghỉ giữa các câu (Pause)',
              value: state.pauseSec,
              min: 0.0,
              max: 1.5,
              formatValue: (v) => '${v.toStringAsFixed(2)}s',
              onChanged: ctrl.setPauseSec,
            ),
            Divider(color: c.border, height: 16),
            AppToggleRow(
              label: 'Khóa cứng mốc thời gian (Lock Timeline Auto-Speed)',
              subtitle: 'Tự động tăng tốc các câu dài để không tràn sang mốc câu tiếp theo',
              value: state.isTimelineLocked,
              onChanged: (v) => ctrl.toggleLockTimeline(v),
            ),
          ],
        ),
      ],
    );
  }
}

