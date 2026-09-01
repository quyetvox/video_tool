import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../models/subtitle_segment.dart';
import '../models/app_config.dart';
import '../utils/time_format_utils.dart';
import '../utils/color_parser_utils.dart';
import 'app_kit.dart';
import 'compact_switch.dart';
import 'smart_color_picker_row.dart';

class SubtitleInspectorWidget extends ConsumerStatefulWidget {
  final List<SubtitleSegment> subtitles;
  final double currentTime;
  final int? selectedSubIndex;
  final Function(int index)? onSelectSubIndex;
  final Function(List<SubtitleSegment> subtitles) onSubtitleChange;
  final Function(double timeSec)? onSeekToSubtitle;
  final VoidCallback onTranslateAll;
  final VoidCallback onAutoSync;
  final VoidCallback onSaveSubtitles;
  final bool isSubModified;
  final bool isProcessing;

  const SubtitleInspectorWidget({
    super.key,
    required this.subtitles,
    required this.currentTime,
    this.selectedSubIndex,
    this.onSelectSubIndex,
    required this.onSubtitleChange,
    this.onSeekToSubtitle,
    required this.onTranslateAll,
    required this.onAutoSync,
    required this.onSaveSubtitles,
    this.isSubModified = false,
    this.isProcessing = false,
  });

  @override
  ConsumerState<SubtitleInspectorWidget> createState() => _SubtitleInspectorWidgetState();
}

class _SubtitleInspectorWidgetState extends ConsumerState<SubtitleInspectorWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int? _editingIndex;
  String _sourceLang = 'auto';
  String _targetLang = 'vi';

  // Controllers for editing active timecodes
  final TextEditingController _startTimeCtrl = TextEditingController();
  final TextEditingController _endTimeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    super.dispose();
  }

  void _updateItemText(int idx, {String? textVi, String? textSecondary, String? textOrig}) {
    final list = [...widget.subtitles];
    if (idx >= 0 && idx < list.length) {
      list[idx] = list[idx].copyWith(
        textVi: textVi,
        textSecondary: textSecondary,
        text: textOrig,
      );
      widget.onSubtitleChange(list);
    }
  }

  void _updateItemTime(int idx, {double? start, double? end}) {
    final list = [...widget.subtitles];
    if (idx >= 0 && idx < list.length) {
      final current = list[idx];
      final newStart = start ?? current.start;
      final newEnd = end ?? current.end;
      if (newEnd >= newStart) {
        list[idx] = current.copyWith(start: newStart, end: newEnd);
        widget.onSubtitleChange(list);
      }
    }
  }

  void _toggleSpeaker(int idx) {
    final list = [...widget.subtitles];
    if (idx >= 0 && idx < list.length) {
      final current = list[idx];
      final raw = current.speaker.toLowerCase();
      final String nextSpeaker;
      final String nextGender;
      if (raw == 'nam' || raw == 'male' || current.gender == 'male') {
        nextSpeaker = 'Nữ';
        nextGender = 'female';
      } else if (raw == 'nữ' || raw == 'nu' || raw == 'female' || current.gender == 'female') {
        nextSpeaker = 'Nam';
        nextGender = 'male';
      } else {
        nextSpeaker = 'Nữ';
        nextGender = 'female';
      }
      list[idx] = current.copyWith(
        speaker: nextSpeaker,
        gender: nextGender,
      );
      widget.onSubtitleChange(list);
    }
  }

  Widget _buildSpeakerBadge(SubtitleSegment sub, int idx) {
    final rawSpeaker = sub.speaker.trim();
    final rawGender = sub.gender.trim().toLowerCase();

    final isMale = rawSpeaker.toLowerCase() == 'nam' || rawSpeaker.toLowerCase() == 'male' || rawGender == 'male';
    final isFemale = rawSpeaker.toLowerCase() == 'nữ' || rawSpeaker.toLowerCase() == 'nu' || rawSpeaker.toLowerCase() == 'female' || rawGender == 'female';

    final String label;
    final Color color;
    final Color bgColor;
    final Color borderColor;

    if (isMale) {
      label = '👨 Nam';
      color = const Color(0xFF38BDF8);
      bgColor = const Color(0xFF38BDF8).withOpacity(0.15);
      borderColor = const Color(0xFF38BDF8).withOpacity(0.4);
    } else if (isFemale) {
      label = '👩 Nữ';
      color = const Color(0xFFF472B6);
      bgColor = const Color(0xFFF472B6).withOpacity(0.15);
      borderColor = const Color(0xFFF472B6).withOpacity(0.4);
    } else if (rawSpeaker.isNotEmpty) {
      label = '👤 $rawSpeaker';
      color = const Color(0xFFA78BFA);
      bgColor = const Color(0xFFA78BFA).withOpacity(0.15);
      borderColor = const Color(0xFFA78BFA).withOpacity(0.4);
    } else {
      label = '👤 Mặc định';
      color = const Color(0xFF94A3B8);
      bgColor = const Color(0xFF94A3B8).withOpacity(0.12);
      borderColor = const Color(0xFF94A3B8).withOpacity(0.3);
    }

    return InkWell(
      onTap: () => _toggleSpeaker(idx),
      borderRadius: BorderRadius.circular(4),
      child: Tooltip(
        message: 'Click để đổi người nói (Nam ↔ Nữ)',
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  void _startEditing(int idx) {
    final sub = widget.subtitles[idx];
    _startTimeCtrl.text = TimeFormatUtils.formatSubtitleTime(sub.start);
    _endTimeCtrl.text = TimeFormatUtils.formatSubtitleTime(sub.end);
    setState(() => _editingIndex = idx);
  }

  void _handleDelete(int idx) {
    final list = [...widget.subtitles]..removeAt(idx);
    widget.onSubtitleChange(list);
    if (_editingIndex == idx) setState(() => _editingIndex = null);
  }

  void _handleAddSegment() {
    final lastEnd = widget.subtitles.isNotEmpty ? widget.subtitles.last.end : widget.currentTime;
    final newSeg = SubtitleSegment(
      id: widget.subtitles.length + 1,
      start: widget.currentTime > 0 ? widget.currentTime : lastEnd,
      end: (widget.currentTime > 0 ? widget.currentTime : lastEnd) + 3.0,
      text: '',
      textVi: '',
      textSecondary: '',
    );
    final list = [...widget.subtitles, newSeg]..sort((a, b) => a.start.compareTo(b.start));
    widget.onSubtitleChange(list);
    _startEditing(list.indexOf(newSeg));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
      ),
      child: Column(
        children: [
          // ── TAB HEADER ──
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
              tabs: const [
                Tab(text: '📝 Subtitles'),
                Tab(text: '📐 Subtitle Style'),
                Tab(text: '🖼️ Inpaint'),
                Tab(text: '🎙️ Voice & Audio'),
                Tab(text: '⚙️ Video & Engine'),
              ],
            ),
          ),

          // ── TAB VIEWS ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── SUBTAB 1: SUBTITLES ──
                _buildSubtitlesTab(config),

                // ── SUBTAB 2: SUBTITLE STYLE ──
                _buildSubtitleStyleTab(config),

                // ── SUBTAB 3: INPAINT ──
                _buildInpaintTab(config),

                // ── SUBTAB 4: VOICE & AUDIO ──
                _buildVoiceAudioTab(config),

                // ── SUBTAB 5: VIDEO & ENGINE ──
                _buildVideoEngineTab(config),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 1: SUBTITLES IMPLEMENTATION (INLINE TIMECODE IN/OUT EDITING) ────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSubtitlesTab(AppConfig config) {
    final notifier = ref.read(configProvider.notifier);
    final c = AppColors.of(context);
    return Column(
      children: [
        // Language Selector & Translate All Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
              Text('From:', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
              const SizedBox(width: 4),
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.surfaceLight, borderRadius: BorderRadius.circular(4)),
                child: DropdownButton<String>(
                  value: _sourceLang,
                  underline: const SizedBox(),
                  dropdownColor: c.surface,
                  style: TextStyle(color: c.textPrimary, fontSize: 10.5),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('🌐 Auto Detect')),
                    DropdownMenuItem(value: 'zh', child: Text('🇨🇳 Tiếng Trung')),
                    DropdownMenuItem(value: 'en', child: Text('🇬🇧 Tiếng Anh')),
                    DropdownMenuItem(value: 'ja', child: Text('🇯🇵 Tiếng Nhật')),
                    DropdownMenuItem(value: 'ko', child: Text('🇰🇷 Tiếng Hàn')),
                  ],
                  onChanged: (v) => setState(() => _sourceLang = v!),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward, size: 10, color: AppColors.textMuted),
              const SizedBox(width: 6),
              const Text('To:', style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
              const SizedBox(width: 4),
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(4)),
                child: DropdownButton<String>(
                  value: _targetLang,
                  underline: const SizedBox(),
                  dropdownColor: AppColors.surfaceLight,
                  style: const TextStyle(color: Colors.white, fontSize: 10.5),
                  items: const [
                    DropdownMenuItem(value: 'vi', child: Text('🇻🇳 Tiếng Việt')),
                    DropdownMenuItem(value: 'en', child: Text('🇬🇧 English')),
                  ],
                  onChanged: (v) => setState(() => _targetLang = v!),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: ['dynamic', 'couple', 'family_parent_child', 'friends', 'formal', 'custom'].contains(config.pronounMode)
                        ? config.pronounMode
                        : 'dynamic',
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: AppColors.primary, fontSize: 10.5, fontWeight: FontWeight.w500),
                    icon: const Icon(Icons.arrow_drop_down, size: 12, color: AppColors.primary),
                    items: const [
                      DropdownMenuItem(value: 'dynamic', child: Text('🎭 Xưng hô: Tự động')),
                      DropdownMenuItem(value: 'couple', child: Text('💑 Cặp đôi (Anh - Em)')),
                      DropdownMenuItem(value: 'family_parent_child', child: Text('👨‍👩‍👧 Gia đình (Bố/Mẹ - Con)')),
                      DropdownMenuItem(value: 'friends', child: Text('👥 Bạn bè (Mình - Cậu)')),
                      DropdownMenuItem(value: 'formal', child: Text('💼 Trang trọng (Tôi - Quý vị)')),
                      DropdownMenuItem(value: 'custom', child: Text('✍️ Tùy chỉnh')),
                    ],
                    onChanged: (v) {
                      if (v != null) notifier.setField((c) => c.copyWith(pronounMode: v));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

        // Subtitle Items List
        Expanded(
          child: widget.subtitles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.subtitles_off_outlined, size: 32, color: AppColors.textMuted),
                      const SizedBox(height: 8),
                      const Text('Chưa có dữ liệu phụ đề.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                      const SizedBox(height: 4),
                      const Text('Hãy chạy nhận diện giọng nói hoặc OCR để trích xuất.', style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 12),
                        label: const Text('Thêm Phụ Đề Thủ Công', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        ),
                        onPressed: _handleAddSegment,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: widget.subtitles.length,
                  itemBuilder: (ctx, idx) {
                    final sub = widget.subtitles[idx];
                    final isActive = widget.currentTime >= sub.start && widget.currentTime <= sub.end;
                    final isEditing = _editingIndex == idx;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.surfaceDark,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isActive
                              ? c.primary
                              : (isEditing ? c.primaryDark : c.border),
                          width: isActive || isEditing ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── ROW 1: INDEX + TIMECODE EDITING + IN/OUT BUTTONS + ACTIONS ──
                          Row(
                            children: [
                              Text('#${idx + 1}', style: TextStyle(color: c.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),

                              // Start Time (In)
                              if (isEditing)
                                SizedBox(
                                  width: 84,
                                  height: 22,
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c.surfaceLight,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: c.primary),
                                    ),
                                    child: TextField(
                                      controller: _startTimeCtrl,
                                      textAlignVertical: TextAlignVertical.center,
                                      style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: c.primary),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (val) {
                                        _updateItemTime(idx, start: TimeFormatUtils.parseTimecodeToSeconds(val));
                                      },
                                    ),
                                  ),
                                )
                              else
                                InkWell(
                                  onTap: () => widget.onSeekToSubtitle?.call(sub.start),
                                  onDoubleTap: () => _startEditing(idx),
                                  child: Text(
                                    TimeFormatUtils.formatSubtitleTime(sub.start),
                                    style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: c.textSecondary, fontWeight: FontWeight.w400),
                                  ),
                                ),

                              // Quick In Grab Button
                              InkWell(
                                onTap: () {
                                  _updateItemTime(idx, start: widget.currentTime);
                                  if (isEditing) _startTimeCtrl.text = TimeFormatUtils.formatSubtitleTime(widget.currentTime);
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: c.surfaceLight,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: c.primary.withOpacity(0.5)),
                                  ),
                                  child: Text('⏱️ In', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: c.primary)),
                                ),
                              ),

                              Text('➔', style: TextStyle(color: c.textMuted, fontSize: 9.5)),

                              // End Time (Out)
                              if (isEditing)
                                SizedBox(
                                  width: 84,
                                  height: 22,
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c.surfaceLight,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: c.primaryDark),
                                    ),
                                    child: TextField(
                                      controller: _endTimeCtrl,
                                      textAlignVertical: TextAlignVertical.center,
                                      style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: c.primaryDark),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (val) {
                                        _updateItemTime(idx, end: TimeFormatUtils.parseTimecodeToSeconds(val));
                                      },
                                    ),
                                  ),
                                )
                              else
                                InkWell(
                                  onTap: () => widget.onSeekToSubtitle?.call(sub.end),
                                  onDoubleTap: () => _startEditing(idx),
                                  child: Text(
                                    TimeFormatUtils.formatSubtitleTime(sub.end),
                                    style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: c.textSecondary, fontWeight: FontWeight.w400),
                                  ),
                                ),

                              // Quick Out Grab Button
                              InkWell(
                                onTap: () {
                                  _updateItemTime(idx, end: widget.currentTime);
                                  if (isEditing) _endTimeCtrl.text = TimeFormatUtils.formatSubtitleTime(widget.currentTime);
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: c.surfaceLight,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: c.primaryDark.withOpacity(0.5)),
                                  ),
                                  child: Text('⏱️ Out', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: c.primaryDark)),
                                ),
                              ),

                              // Speaker / Gender Badge
                              _buildSpeakerBadge(sub, idx),

                              const Spacer(),

                              // Edit Mode Toggle Button
                              IconButton(
                                icon: Icon(isEditing ? Icons.check_circle : Icons.edit, size: 14, color: isEditing ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                                tooltip: isEditing ? 'Hoàn tất sửa' : 'Chỉnh sửa chi tiết',
                                onPressed: () {
                                  if (isEditing) {
                                    final sSec = TimeFormatUtils.parseTimecodeToSeconds(_startTimeCtrl.text);
                                    final eSec = TimeFormatUtils.parseTimecodeToSeconds(_endTimeCtrl.text);
                                    _updateItemTime(idx, start: sSec, end: eSec);
                                    setState(() => _editingIndex = null);
                                  } else {
                                    _startEditing(idx);
                                  }
                                },
                              ),

                              // Delete Button
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                                tooltip: 'Xóa câu này',
                                onPressed: () => _handleDelete(idx),
                              ),
                            ],
                          ),

                          const SizedBox(height: 5),

                          // ── ROW 2: 3-TIER MULTILINGUAL TEXT ──
                          // 1. Primary Translation (Tiếng Việt)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFACC15).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text('Chính', style: TextStyle(color: Color(0xFFFACC15), fontSize: 9.5, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: isEditing
                                    ? _SubtitleInlineEditor(
                                        key: ValueKey('vi_${sub.id}_$idx'),
                                        text: sub.textVi,
                                        style: TextStyle(
                                          color: AppColors.isDark(context) ? const Color(0xFFFEF08A) : const Color(0xFFB45309),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          hintText: 'Bản dịch chính (Tiếng Việt)...',
                                          hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                                          border: UnderlineInputBorder(borderSide: BorderSide(color: c.primary)),
                                        ),
                                        onChanged: (v) => _updateItemText(idx, textVi: v),
                                      )
                                    : Text(
                                        sub.textVi.isNotEmpty ? sub.textVi : '(Chưa có bản dịch chính)',
                                        style: TextStyle(
                                          color: sub.textVi.isNotEmpty
                                              ? (AppColors.isDark(context) ? const Color(0xFFFEF08A) : const Color(0xFF92400E))
                                              : c.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ],
                          ),

                          // 2. Secondary Translation (Tiếng Anh - Song ngữ)
                          if (isEditing || sub.textSecondary.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF38BDF8).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('Phụ', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: isEditing
                                      ? _SubtitleInlineEditor(
                                          key: ValueKey('sec_${sub.id}_$idx'),
                                          text: sub.textSecondary,
                                          style: TextStyle(
                                            color: AppColors.isDark(context) ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
                                            fontSize: 11,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                            hintText: 'Bản dịch phụ (Tiếng Anh song ngữ)...',
                                            hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                                            border: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                                          ),
                                          onChanged: (v) => _updateItemText(idx, textSecondary: v),
                                        )
                                      : Text(
                                          sub.textSecondary,
                                          style: TextStyle(
                                            color: AppColors.isDark(context) ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
                                            fontSize: 11,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ],

                          // 3. Original Text (OCR / Whisper)
                          if (isEditing || sub.text.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              sub.text.isNotEmpty ? 'Gốc: ${sub.text}' : 'Gốc: [Trống]',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.surfaceDark,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                AppButton.outlined(
                  label: 'Thêm Phụ Đề',
                  icon: Icons.add,
                  height: 28,
                  fontSize: 11,
                  onPressed: _handleAddSegment,
                ),
                const SizedBox(width: 8),
                AppButton.secondary(
                  label: 'Dịch Toàn Bộ (AI)',
                  icon: Icons.bolt,
                  height: 28,
                  fontSize: 11,
                  isLoading: widget.isProcessing,
                  onPressed: widget.isProcessing ? null : widget.onTranslateAll,
                ),
                const SizedBox(width: 8),
                AppButton.success(
                  label: 'Lưu & Render (~2s)',
                  icon: Icons.flash_on,
                  height: 28,
                  fontSize: 11,
                  onPressed: widget.onSaveSubtitles,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 2: SUBTITLE STYLE (Primary + Secondary expandable) ─────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildSubtitleStyleTab(AppConfig config) {
    final notifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 🅰️ PRIMARY SUBTITLE ──
        _buildSectionHeader('🅰️ PHỤ ĐỀ CHÍNH (PRIMARY SUBTITLE)'),
        const SizedBox(height: 8),

        const SizedBox(height: 8),

        _buildToggleRow(
          label: 'Bật Hiển Thị Sub Chính',
          value: config.showSubtitle,
          onChanged: (val) => notifier.setField((c) => c.copyWith(showSubtitle: val)),
        ),

        if (config.showSubtitle) ...[
          const SizedBox(height: 4),
          _buildToggleRow(
            label: 'Vị Trí Thủ Công (Manual Region)',
            subtitle: 'Tắt = Tự động bám Inpaint Box',
            value: config.subtitleRegion != null,
            onChanged: (val) {
              if (val) {
                notifier.setField((c) => c.copyWith(
                    subtitleRegion:
                        config.inpaintRegion ?? [0.76, 0.05, 0.86, 0.95]));
              } else {
                notifier.setField((c) => c.copyWith(setSubtitleRegionNull: true));
              }
            },
          ),

          if (config.subtitleRegion != null) ...[
            _buildRegionEditRow(
              label: 'Tọa Độ Sub Chính (subtitle.region):',
              region: config.subtitleRegion!,
              layerType: FrameLayerType.primarySub,
              onReset: null,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '↳ Tự động căn giữa theo Hộp Inpaint (Auto Focus)',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic),
              ),
            ),

          // Font + Size in row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildDropdownRow(
                  label: 'Font Chữ Sub Chính:',
                  value: config.fontName.isNotEmpty ? config.fontName : 'Arial',
                  items: ref.watch(availableFontsProvider).map((f) {
                    return DropdownMenuItem(
                      value: f.name,
                      child: Row(
                        children: [
                          if (f.isCustom) ...[
                            const Icon(Icons.folder, size: 12, color: AppColors.primary),
                            const SizedBox(width: 4),
                          ],
                          Text(f.name, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) =>
                      notifier.setField((c) => c.copyWith(fontName: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: _buildTextFormInput(
                  label: 'Cỡ Chữ (px):',
                  hint: 'Auto',
                  value: config.fontSize,
                  onChanged: (v) =>
                      notifier.setField((c) => c.copyWith(fontSize: v)),
                ),
              ),
            ],
          ),

          SmartColorPickerRow(
            label: 'Màu Chữ (font_color):',
            currentColor: config.fontColor,
            presets: const [
              ColorPreset(
                  label: '⚪ Trắng (&H00FFFFFF)',
                  code: '&H00FFFFFF',
                  previewColor: Colors.white),
              ColorPreset(
                  label: '🟡 Vàng (&H0000FFFF)',
                  code: '&H0000FFFF',
                  previewColor: Color(0xFFFFFF00)),
              ColorPreset(
                  label: '🔵 Cyan (&H00FFFF00)',
                  code: '&H00FFFF00',
                  previewColor: Color(0xFF00FFFF)),
              ColorPreset(
                  label: '🔴 Đỏ (&H000000FF)',
                  code: '&H000000FF',
                  previewColor: Color(0xFFFF0000)),
              ColorPreset(
                  label: '⚫ Đen (&H00000000)',
                  code: '&H00000000',
                  previewColor: Colors.black),
            ],
            onChanged: (v) =>
                notifier.setField((c) => c.copyWith(fontColor: v)),
          ),
        ],

        const Divider(color: AppColors.border, height: 20),

        // ── 🅱️ SECONDARY SUBTITLE ──
        _buildSectionHeader('🅱️ PHỤ ĐỀ PHỤ SONG NGỮ (SECONDARY SUBTITLE)'),
        const SizedBox(height: 8),

        _buildToggleRow(
          label: 'Bật Hiển Thị Sub Phụ (Song Ngữ)',
          value: config.subtitleSecondaryShow,
          onChanged: (val) => notifier.setField(
              (c) => c.copyWith(subtitleSecondaryShow: val)),
        ),

        if (config.subtitleSecondaryShow) ...[
          _buildToggleRow(
            label: 'Vị Trí Thủ Công Sub Phụ (Manual Region)',
            subtitle: 'Tắt = Tự động bám theo Sub Chính',
            value: config.subtitleSecondaryRegion != null,
            onChanged: (val) {
              if (val) {
                notifier.setField((c) => c.copyWith(
                    subtitleSecondaryRegion: [0.87, 0.05, 0.95, 0.95]));
              } else {
                notifier.setField(
                    (c) => c.copyWith(setSubtitleSecondaryRegionNull: true));
              }
            },
          ),

          if (config.subtitleSecondaryRegion != null) ...[
            _buildRegionEditRow(
              label: 'Tọa Độ Sub Phụ (subtitle.secondary.region):',
              region: config.subtitleSecondaryRegion!,
              layerType: FrameLayerType.secondarySub,
              onReset: null,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '↳ Tự động bám theo Sub Chính (cách box_gap px)',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic),
              ),
            ),

          // Secondary font dropdown
          _buildDropdownRow(
            label: 'Font Chữ Sub Phụ:',
            value: config.subtitleSecondaryFontName.isNotEmpty ? config.subtitleSecondaryFontName : config.fontName,
            items: ref.watch(availableFontsProvider).map((f) {
              return DropdownMenuItem(
                value: f.name,
                child: Row(
                  children: [
                    if (f.isCustom) ...[
                      const Icon(Icons.folder, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(f.name, overflow: TextOverflow.ellipsis),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) => notifier.setField((c) => c.copyWith(subtitleSecondaryFontName: v)),
          ),
          const SizedBox(height: 6),

          _buildSliderRow(
              'Tỷ Lệ Cỡ Chữ Phụ So Với Chính:',
              config.subtitleSecondaryFontScale,
              0.5,
              1.0, (v) {
            notifier.setField((c) => c.copyWith(
                subtitleSecondaryFontScale:
                    double.parse(v.toStringAsFixed(2))));
          }, format: (v) => '${(v * 100).toInt()}%'),

          SmartColorPickerRow(
            label: 'Màu Chữ Phụ (font_color):',
            currentColor: config.subtitleSecondaryFontColor,
            presets: const [
              ColorPreset(
                  label: '⚪ Trắng Xám (&H00D0D0D0)',
                  code: '&H00D0D0D0',
                  previewColor: Color(0xFFD0D0D0)),
              ColorPreset(
                  label: '⚪ Trắng (&H00FFFFFF)',
                  code: '&H00FFFFFF',
                  previewColor: Colors.white),
              ColorPreset(
                  label: '🟡 Vàng (&H0000FFFF)',
                  code: '&H0000FFFF',
                  previewColor: Color(0xFFFFFF00)),
            ],
            onChanged: (v) => notifier
                .setField((c) => c.copyWith(subtitleSecondaryFontColor: v)),
          ),
        ],

        const Divider(color: AppColors.border, height: 20),

        // ── LAYOUT & TIMING ──
        _buildSectionHeader('🔀 BỐ CỤC SONG NGỮ & THỜI GIAN (LAYOUT)'),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _buildDropdownRow(
                label: 'Thứ Tự Dòng:',
                value: config.subtitleOrder,
                items: const [
                  DropdownMenuItem(
                      value: 'primary_top',
                      child: Text('Chính Trên, Phụ Dưới')),
                  DropdownMenuItem(
                      value: 'secondary_top',
                      child: Text('Phụ Trên, Chính Dưới')),
                ],
                onChanged: (v) =>
                    notifier.setField((c) => c.copyWith(subtitleOrder: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextFormInput(
                label: 'Khoảng Cách 2 Hộp (px):',
                hint: '8',
                value: config.boxGap.toString(),
                onChanged: (v) => notifier.setField(
                    (c) => c.copyWith(boxGap: int.tryParse(v) ?? 8)),
              ),
            ),
          ],
        ),

        _buildToggleRow(
          label: 'Tách 2 Hộp Nền Riêng Biệt (box_split)',
          value: config.boxSplit,
          onChanged: (val) =>
              notifier.setField((c) => c.copyWith(boxSplit: val)),
        ),

        _buildSliderRow(
            'Ngưỡng Đóng Sub Khi Chuyển Cảnh (max_gap_fill):',
            config.maxGapFill,
            0.2,
            2.0, (v) {
          notifier.setField((c) => c.copyWith(
              maxGapFill: double.parse(v.toStringAsFixed(2))));
        }, format: (v) => '${v.toStringAsFixed(2)}s'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 3: INPAINT (Xóa Sub Cũ + Hộp Nền + Watermark) ─────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildInpaintTab(AppConfig config) {
    final notifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── INPAINT ENGINE & MASTER TOGGLE ──
        _buildSectionHeader('🖼️ XÓA SUB CŨ (INPAINT ENGINE)'),
        const SizedBox(height: 8),

        _buildToggleRow(
          label: 'Bật Xóa Sub Cũ / Hộp Nền (show_box)',
          value: config.inpaintShowBox,
          onChanged: (val) =>
              notifier.setField((c) => c.copyWith(inpaintShowBox: val)),
        ),
        const SizedBox(height: 8),

        _buildDropdownRow(
          label: 'Inpaint Engine:',
          value: config.inpaintEngine,
          items: const [
            DropdownMenuItem(
                value: 'box_color', child: Text('box_color (Hộp Màu Tối)')),
            DropdownMenuItem(
                value: 'ffmpeg_blur', child: Text('ffmpeg_blur (Mờ Kính)')),
            DropdownMenuItem(
                value: 'apple_vision_inpaint',
                child: Text('apple_vision_inpaint (AI Inpaint)')),
            DropdownMenuItem(
                value: 'opencv', child: Text('opencv (CV2 Inpaint)')),
          ],
          onChanged: (v) =>
              notifier.setField((c) => c.copyWith(inpaintEngine: v)),
        ),
        if (config.inpaintEngine == 'ffmpeg_blur')
          const SizedBox(height: 4),
          _buildSliderRow(
              'Độ Mờ Kính (blur_radius):', config.inpaintBlurRadius.toDouble(), 5.0, 40.0,
              (v) {
            notifier.setField((c) => c.copyWith(inpaintBlurRadius: v.toInt()));
          }, format: (v) => '${v.toInt()} px'),

        if (config.inpaintEngine == 'apple_vision_inpaint' ||
            config.inpaintEngine == 'opencv')
          _buildDropdownRow(
            label: 'Thuật Toán Inpaint (Method):',
            value: config.inpaintMethod,
            items: const [
              DropdownMenuItem(
                  value: 'vertical_gradient',
                  child: Text('vertical_gradient (Khử Vệt Sọc - Tự Nhiên)')),
              DropdownMenuItem(
                  value: 'navier_stokes',
                  child: Text('navier_stokes (Dòng Chảy Fluid)')),
              DropdownMenuItem(
                  value: 'telea', child: Text('telea (Fast Marching)')),
            ],
            onChanged: (v) =>
                notifier.setField((c) => c.copyWith(inpaintMethod: v)),
          ),

        // Inpaint Region
        const SizedBox(height: 4),
        _buildRegionEditRow(
          label: 'Vùng Che Sub Cũ (Inpaint Region):',
          region: config.inpaintRegion,
          layerType: FrameLayerType.inpaint,
          onReset: config.inpaintRegion != null
              ? () => notifier
                  .setField((c) => c.copyWith(setInpaintRegionNull: true))
              : null,
          nullLabel: 'Tự động nhận diện (Auto Detect từ OCR)',
        ),

        _buildSliderRow(
            'Nới Lề Dọc (padding_y):', config.inpaintPaddingY, 0.0, 0.1,
            (v) {
          notifier.setField((c) => c.copyWith(
              inpaintPaddingY: double.parse(v.toStringAsFixed(3))));
        }, format: (v) => '${(v * 100).toStringAsFixed(1)}%'),

        // Thời Gian Mở Sớm & Đóng Trễ Hộp Che
        Row(
          children: [
            Expanded(
              child: _buildTextFormInput(
                label: 'Mở Sớm Hộp Inpaint (box_lead_in):',
                hint: '0.25',
                value: config.boxLeadIn.toString(),
                onChanged: (v) => notifier.setField(
                    (c) => c.copyWith(boxLeadIn: double.tryParse(v) ?? 0.25)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextFormInput(
                label: 'Đóng Trễ Hộp Inpaint (box_lead_out):',
                hint: '0.15',
                value: config.boxLeadOut.toString(),
                onChanged: (v) => notifier.setField(
                    (c) => c.copyWith(
                        boxLeadOut: double.tryParse(v) ?? 0.15)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        if (config.inpaintEngine == 'box_color') ...[
          const Divider(color: AppColors.border, height: 20),
          _buildSectionHeader('🎨 CẤU HÌNH HỘP NỀN BOX COLOR'),
          const SizedBox(height: 8),

          SmartColorPickerRow(
            label: 'Màu Nền Box (bg_color):',
            currentColor: config.boxBgColor,
            presets: const [
              ColorPreset(
                  label: '⚫ Đen (black)',
                  code: 'black',
                  previewColor: Colors.black),
              ColorPreset(
                  label: '🌑 Đen Slate (#0f172a)',
                  code: '#0f172a',
                  previewColor: Color(0xFF0F172A)),
              ColorPreset(
                  label: '🔘 Xám Đậm (#1e1e1e)',
                  code: '#1e1e1e',
                  previewColor: Color(0xFF1E1E1E)),
              ColorPreset(
                  label: '⚪ Trắng (white)',
                  code: 'white',
                  previewColor: Colors.white),
            ],
            onChanged: (v) =>
                notifier.setField((c) => c.copyWith(boxBgColor: v)),
          ),

          _buildSliderRow(
              'Độ Đậm Nền (bg_opacity):', config.boxBgOpacity, 0.1, 1.0,
              (v) {
            notifier.setField((c) => c.copyWith(
                boxBgOpacity: double.parse(v.toStringAsFixed(2))));
          }, format: (v) => '${(v * 100).toInt()}%'),

          SmartColorPickerRow(
            label: 'Màu Viền Hộp (border_color):',
            currentColor: config.boxBorderColor,
            presets: const [
              ColorPreset(
                  label: '⚪ Trắng Mờ (&H40FFFFFF)',
                  code: '&H40FFFFFF',
                  previewColor: Color(0xC0FFFFFF)),
              ColorPreset(
                  label: '🟡 Vàng (&H0000FFFF)',
                  code: '&H0000FFFF',
                  previewColor: Color(0xFFFFFF00)),
              ColorPreset(
                  label: '🔵 Cyan (&H00FFFF00)',
                  code: '&H00FFFF00',
                  previewColor: Color(0xFF00FFFF)),
              ColorPreset(
                  label: '🚫 Không Viền (none)',
                  code: 'none',
                  previewColor: Colors.transparent),
            ],
            onChanged: (v) =>
                notifier.setField((c) => c.copyWith(boxBorderColor: v)),
          ),

          Row(
            children: [
              Expanded(
                child: _buildDropdownRow(
                  label: 'Độ Dày Viền:',
                  value: config.boxBorderWidth.toString(),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('1 px (Mảnh)')),
                    DropdownMenuItem(value: '2', child: Text('2 px (Vừa)')),
                    DropdownMenuItem(value: '3', child: Text('3 px (Đậm)')),
                  ],
                  onChanged: (v) => notifier.setField((c) =>
                      c.copyWith(boxBorderWidth: int.tryParse(v ?? '2') ?? 2)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdownRow(
                  label: 'Bo Góc Viền:',
                  value: config.boxBorderRadius.toString(),
                  items: const [
                    DropdownMenuItem(value: '0', child: Text('0 px (Vuông)')),
                    DropdownMenuItem(value: '4', child: Text('4 px')),
                    DropdownMenuItem(
                        value: '8', child: Text('8 px (Mặc định)')),
                    DropdownMenuItem(value: '12', child: Text('12 px (Tròn)')),
                  ],
                  onChanged: (v) => notifier.setField((c) => c.copyWith(
                      boxBorderRadius: int.tryParse(v ?? '8') ?? 8)),
                ),
              ),
            ],
          ),
        ],

        const Divider(color: AppColors.border, height: 24),

        // ── WATERMARK ──
        _buildSectionHeader('3. WATERMARK & BRANDING (LOGO THƯƠNG HIỆU)'),
        const SizedBox(height: 8),

        _buildToggleRow(
          label: 'Bật Watermark / Logo Thương Hiệu (enabled)',
          value: config.watermarkEnabled,
          onChanged: (val) => notifier.setField((c) => c.copyWith(watermarkEnabled: val)),
        ),

        if (config.watermarkEnabled) ...[
          // Vùng đặt Watermark (Region)
          _buildRegionEditRow(
            label: 'Vùng Đặt Watermark (watermark.region):',
            region: config.watermarkRegion,
            layerType: FrameLayerType.watermark,
            onReset: () => notifier.setField((c) => c.copyWith(watermarkRegion: [0.02, 0.85, 0.05, 0.95])),
          ),

          // Logo Image Path with File Picker (Ưu tiên 1)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildTextFormInput(
                  label: 'Đường Dẫn Ảnh Logo PNG (Ưu Tiên 1):',
                  hint: 'assets/.../logo.png',
                  value: config.watermarkImage,
                  onChanged: (v) => notifier.setField((c) => c.copyWith(watermarkImage: v)),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: AppColors.border, width: 0.8)),
                  ),
                  icon: const Icon(Icons.folder_open, size: 14, color: AppColors.primary),
                  label: const Text('Chọn Ảnh...', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (result != null && result.files.single.path != null) {
                      notifier.setField((c) => c.copyWith(watermarkImage: result.files.single.path!));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Watermark Text (Ưu tiên 2)
          _buildTextFormInput(
            label: 'Chữ Hiển Thị Nếu Không Có Ảnh (Ưu Tiên 2):',
            hint: 'Sub-Video AI',
            value: config.watermarkText,
            onChanged: (v) => notifier.setField((c) => c.copyWith(watermarkText: v)),
          ),
          const SizedBox(height: 6),

          // Font Name Dropdown
          _buildDropdownRow(
            label: 'Font Chữ Watermark (font_name):',
            value: config.watermarkFontName.isNotEmpty ? config.watermarkFontName : 'Arial',
            items: ref.watch(availableFontsProvider).map((f) {
              return DropdownMenuItem(
                value: f.name,
                child: Row(
                  children: [
                    if (f.isCustom) ...[
                      const Icon(Icons.folder, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(f.name, overflow: TextOverflow.ellipsis),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) => notifier.setField((c) => c.copyWith(watermarkFontName: v)),
          ),

          // Smart Color Picker for Watermark Font Color
          SmartColorPickerRow(
            label: 'Màu Chữ Watermark (font_color):',
            currentColor: config.watermarkFontColor,
            preferAssFormat: false,
            presets: const [
              ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
              ColorPreset(label: '🟡 Vàng (yellow)', code: 'yellow', previewColor: Color(0xFFFFFF00)),
              ColorPreset(label: '🔵 Xanh Cyan (cyan)', code: 'cyan', previewColor: Color(0xFF00FFFF)),
              ColorPreset(label: '🔴 Đỏ (red)', code: 'red', previewColor: Color(0xFFFF0000)),
              ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
            ],
            onChanged: (v) => notifier.setField((c) => c.copyWith(watermarkFontColor: v)),
          ),

          // Opacity Slider
          _buildSliderRow('Độ Đậm Logo / Text (Opacity):', config.watermarkOpacity, 0.1, 1.0, (v) {
            notifier.setField((c) => c.copyWith(watermarkOpacity: double.parse(v.toStringAsFixed(2))));
          }, format: (v) => '${(v * 100).toInt()}%'),

          // Blur BG Toggle
          _buildToggleRow(
            label: 'Nền Mờ Kính Cho Watermark (blur_bg)',
            subtitle: 'Làm mờ nền đằng sau để nổi bật logo thương hiệu',
            value: config.watermarkBlurBg,
            onChanged: (val) => notifier.setField((c) => c.copyWith(watermarkBlurBg: val)),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 3: VOICE & AUDIO (1:1 CONFIG.YAML) ─────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildVoiceAudioTab(AppConfig config) {
    final notifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. THUYẾT MINH AI (TTS) ──
        _buildSectionHeader('1. THUYẾT MINH AI (EDGETTS)'),
        const SizedBox(height: 8),

        _buildDropdownRow(
          label: 'Giọng Đọc Mặc Định (tts.voice):',
          value: (config.ttsVoice == 'vi' || config.ttsVoice == 'banmai') ? 'vi-VN-BanMai' : config.ttsVoice,
          items: const [
            DropdownMenuItem(value: 'vi-VN-BanMai', child: Text('🌸 vi-VN-BanMai (Google TTS)')),
            DropdownMenuItem(value: 'vi-VN-HoaiMyNeural', child: Text('🎙️ vi-VN-HoaiMyNeural (EdgeTTS Nữ)')),
            DropdownMenuItem(value: 'vi-VN-NamMinhNeural', child: Text('🎙️ vi-VN-NamMinhNeural (EdgeTTS Nam)')),
            DropdownMenuItem(value: '0', child: Text('🔇 0 (Tắt TTS - Giữ 100% Âm Gốc)')),
          ],
          onChanged: (v) => notifier.setField((c) => c.copyWith(ttsVoice: v)),
        ),

        // Speed Factor
        _buildSliderRow('Tốc Độ Đọc (Speed Factor):', config.ttsSpeedFactor, 0.8, 2.0, (v) {
          notifier.setField((c) => c.copyWith(ttsSpeedFactor: double.parse(v.toStringAsFixed(2))));
        }, format: (v) => '${v.toStringAsFixed(2)}x'),

        // Voice-over Delay
        _buildSliderRow('Độ Trễ Giọng Đọc (delay_sec):', config.ttsDelay, 0.0, 0.8, (v) {
          notifier.setField((c) => c.copyWith(ttsDelay: double.parse(v.toStringAsFixed(2))));
        }, format: (v) => '${v.toStringAsFixed(2)}s'),

        _buildToggleRow(
          label: 'Tự Động Đổi Giọng Theo Giới Tính (enable_gender)',
          value: config.enableGenderTts,
          onChanged: (val) => notifier.setField((c) => c.copyWith(enableGenderTts: val)),
        ),

        if (config.enableGenderTts) ...[
          _buildDropdownRow(
            label: 'Giọng Nam:',
            value: config.ttsVoiceMale,
            items: const [
              DropdownMenuItem(value: 'vi-VN-NamMinhNeural', child: Text('🎙️ vi-VN-NamMinhNeural (Nam EdgeTTS)')),
              DropdownMenuItem(value: 'vi-VN-BanMai', child: Text('🌸 vi-VN-BanMai (Google TTS)')),
              DropdownMenuItem(value: 'vi-VN-HoaiMyNeural', child: Text('🎙️ vi-VN-HoaiMyNeural (Hoài My)')),
            ],
            onChanged: (v) => notifier.setField((c) => c.copyWith(ttsVoiceMale: v)),
          ),
          _buildDropdownRow(
            label: 'Giọng Nữ:',
            value: (config.ttsVoiceFemale == 'vi' || config.ttsVoiceFemale == 'banmai') ? 'vi-VN-BanMai' : config.ttsVoiceFemale,
            items: const [
              DropdownMenuItem(value: 'vi-VN-HoaiMyNeural', child: Text('🎙️ vi-VN-HoaiMyNeural (Hoài My - Nữ EdgeTTS)')),
              DropdownMenuItem(value: 'vi-VN-BanMai', child: Text('🌸 vi-VN-BanMai (Google TTS)')),
              DropdownMenuItem(value: 'vi-VN-NamMinhNeural', child: Text('🎙️ vi-VN-NamMinhNeural (Nam Minh)')),
            ],
            onChanged: (v) => notifier.setField((c) => c.copyWith(ttsVoiceFemale: v)),
          ),
        ],

        const Divider(color: AppColors.border, height: 24),

        // ── 2. BỘ TRỘN ÂM LƯỢNG (AUDIO MIXER) ──
        _buildSectionHeader('2. BỘ TRỘN ÂM LƯỢNG (AUDIO MIXER)'),
        const SizedBox(height: 8),

        _buildVolumeRow('🎙️ Giọng Đọc TTS (tts_voice):', config.audioTtsVoiceVolume, (v) {
          notifier.setField((c) => c.copyWith(audioTtsVoiceVolume: double.parse(v.toStringAsFixed(2))));
        }),
        _buildVolumeRow('🗣️ Giọng Thoại Gốc (original_voice):', config.audioOriginalVoiceVolume, (v) {
          notifier.setField((c) => c.copyWith(audioOriginalVoiceVolume: double.parse(v.toStringAsFixed(2))));
        }),
        _buildVolumeRow('🎵 Nhạc Nền BGM (music):', config.audioMusicVolume, (v) {
          notifier.setField((c) => c.copyWith(audioMusicVolume: double.parse(v.toStringAsFixed(2))));
        }),
        _buildVolumeRow('🍃 Âm Môi Trường (ambient):', config.audioAmbientVolume, (v) {
          notifier.setField((c) => c.copyWith(audioAmbientVolume: double.parse(v.toStringAsFixed(2))));
        }),

        const Divider(color: AppColors.border, height: 24),

        // ── 3. BỘ LỌC ÂM THANH (FILTERS) ──
        _buildSectionHeader('3. BỘ LỌC & KHỬ NHIỄU ÂM THANH (FILTERS)'),
        const SizedBox(height: 8),

        _buildSliderRow('Độ Lọc Tiếng Ù Spectral Gate (noise_reduction):', config.noiseReductionStrength, 0.0, 1.0, (v) {
          notifier.setField((c) => c.copyWith(noiseReductionStrength: double.parse(v.toStringAsFixed(2))));
        }, format: (v) => '${(v * 100).toInt()}%'),

        _buildSliderRow('Ngưỡng Tách Môi Trường vs Nhạc (ambient_threshold):', config.ambientSplitThreshold, 0.0, 1.0, (v) {
          notifier.setField((c) => c.copyWith(ambientSplitThreshold: double.parse(v.toStringAsFixed(2))));
        }, format: (v) => '${(v * 100).toInt()}%'),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── SUBTAB 4: VIDEO & ENGINE (1:1 CONFIG.YAML) ────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildVideoEngineTab(AppConfig config) {
    final notifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. CẤU HÌNH XUẤT VIDEO (APP) ──
        _buildSectionHeader('1. CẤU HÌNH XUẤT VIDEO (APP)'),
        const SizedBox(height: 8),

        _buildDropdownRow(
          label: 'Thiết Bị Xử Lý (Device):',
          value: config.device,
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('⚡ auto (Tự Động MPS / CUDA / CPU)')),
            DropdownMenuItem(value: 'mps', child: Text('🍏 mps (Apple Silicon GPU Accelerated)')),
            DropdownMenuItem(value: 'cuda', child: Text('🟢 cuda (NVIDIA GPU)')),
            DropdownMenuItem(value: 'cpu', child: Text('💻 cpu (Xử Lý Thuần CPU)')),
          ],
          onChanged: (v) => notifier.setField((c) => c.copyWith(device: v)),
        ),

        _buildDropdownRow(
          label: 'Độ Nét Video Bitrate (video_bitrate):',
          value: config.videoBitrate,
          items: const [
            DropdownMenuItem(value: '4.0M', child: Text('🎬 4.0M (TikTok HD Sắc Nét Căng - Khuyên Dùng)')),
            DropdownMenuItem(value: '2.5M', child: Text('📺 2.5M (Chuẩn Standard)')),
            DropdownMenuItem(value: '1.5M', child: Text('📦 1.5M (Dung Lượng Nhẹ)')),
          ],
          onChanged: (v) => notifier.setField((c) => c.copyWith(videoBitrate: v)),
        ),

        Row(
          children: [
            Expanded(
              child: _buildDropdownRow(
                label: 'Ngôn Ngữ Chính (Primary):',
                value: config.targetLang,
                items: const [
                  DropdownMenuItem(value: 'vi', child: Text('🇻🇳 vi (Tiếng Việt)')),
                  DropdownMenuItem(value: 'en', child: Text('🇬🇧 en (Tiếng Anh)')),
                ],
                onChanged: (v) => notifier.setField((c) => c.copyWith(targetLang: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownRow(
                label: 'Ngôn Ngữ Phụ (Song Ngữ):',
                value: config.secondaryLang,
                items: const [
                  DropdownMenuItem(value: '', child: Text('(Không - Chỉ Đơn Ngữ)')),
                  DropdownMenuItem(value: 'en', child: Text('🇬🇧 en (Tiếng Anh)')),
                  DropdownMenuItem(value: 'zh', child: Text('🇨🇳 zh (Tiếng Trung)')),
                  DropdownMenuItem(value: 'ja', child: Text('🇯🇵 ja (Tiếng Nhật)')),
                  DropdownMenuItem(value: 'ko', child: Text('🇰🇷 ko (Tiếng Hàn)')),
                ],
                onChanged: (v) => notifier.setField((c) => c.copyWith(secondaryLang: v)),
              ),
            ),
          ],
        ),

        _buildToggleRow(
          label: 'Chế Độ Dịch Sub Hình Ảnh Siêu Tốc (ocr_only)',
          subtitle: 'Bỏ qua Whisper & Demucs (~0s), giữ 100% âm thanh gốc',
          value: config.ocrOnly,
          onChanged: (val) => notifier.setField((c) => c.copyWith(ocrOnly: val)),
        ),

        const Divider(color: AppColors.border, height: 24),

        // ── 2. NHẬN DIỆN GIỌNG NÓI (WHISPER ASR) ──
        _buildSectionHeader('2. NHẬN DIỆN GIỌNG NÓI (WHISPER ASR)'),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _buildDropdownRow(
                label: 'ASR Engine:',
                value: config.asrEngine,
                items: const [
                  DropdownMenuItem(value: 'mlx-whisper', child: Text('mlx-whisper (Apple M-Chip)')),
                  DropdownMenuItem(value: 'whisper', child: Text('whisper (OpenAI Standard)')),
                  DropdownMenuItem(value: 'sensevoice', child: Text('sensevoice (Fast Multi-Lang)')),
                ],
                onChanged: (v) => notifier.setField((c) => c.copyWith(asrEngine: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownRow(
                label: 'ASR Model:',
                value: config.asrModel,
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('auto (Khuyên Dùng)')),
                  DropdownMenuItem(value: 'large-v3-turbo', child: Text('large-v3-turbo (Siêu Tốc)')),
                  DropdownMenuItem(value: 'large-v3', child: Text('large-v3 (Chính Xác)')),
                ],
                onChanged: (v) => notifier.setField((c) => c.copyWith(asrModel: v)),
              ),
            ),
          ],
        ),

        const Divider(color: AppColors.border, height: 24),

        // ── 3. DỊCH THUẬT AI (TRANSLATOR LLM) ──
        _buildSectionHeader('3. DỊCH THUẬT AI (TRANSLATOR LLM)'),
        const SizedBox(height: 8),

        _buildDropdownRow(
          label: 'AI Translator Provider (type):',
          value: config.translatorType,
          items: const [
            DropdownMenuItem(value: 'ollama', child: Text('🦙 Ollama Local / Cloud')),
            DropdownMenuItem(value: 'openai', child: Text('⚡ OpenAI (GPT-4o, GPT-4o-mini)')),
            DropdownMenuItem(value: 'gemini', child: Text('✨ Google Gemini')),
            DropdownMenuItem(value: 'groq', child: Text('🚀 Groq Cloud LPU')),
            DropdownMenuItem(value: 'deepseek', child: Text('🐋 DeepSeek API')),
            DropdownMenuItem(value: 'openrouter', child: Text('🌐 OpenRouter API')),
            DropdownMenuItem(value: 'custom', child: Text('🔧 Custom Base URL')),
          ],
          onChanged: (v) {
            if (v == null) return;
            var defaultBaseUrl = config.translatorBaseUrl;
            var defaultModel = config.translatorModel;
            if (v == 'ollama') {
              defaultBaseUrl = 'http://localhost:11434';
              defaultModel = 'gemma4:31b-cloud';
            } else if (v == 'deepseek') {
              defaultBaseUrl = 'https://api.deepseek.com/v1';
              defaultModel = 'deepseek-chat';
            } else if (v == 'groq') {
              defaultBaseUrl = 'https://api.groq.com/openai/v1';
              defaultModel = 'llama-3.3-70b-versatile';
            } else if (v == 'openrouter') {
              defaultBaseUrl = 'https://openrouter.ai/api/v1';
              defaultModel = 'qwen/qwen-2.5-72b-instruct';
            } else if (v == 'gemini') {
              defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
              defaultModel = 'gemini-3.1-flash-lite';
            } else if (v == 'openai') {
              defaultBaseUrl = 'https://api.openai.com/v1';
              defaultModel = 'gpt-4o-mini';
            }
            notifier.setField((c) => c.copyWith(
              translatorType: v,
              translatorBaseUrl: defaultBaseUrl,
              translatorModel: defaultModel,
            ));
          },
        ),

        _buildTextFormInput(
          label: 'Tên Model AI (translator.model):',
          hint: 'gemma4:31b-cloud',
          value: config.translatorModel,
          onChanged: (v) => notifier.setField((c) => c.copyWith(translatorModel: v)),
        ),
        const SizedBox(height: 6),

        _buildTextFormInput(
          label: 'Base URL:',
          hint: 'http://localhost:11434',
          value: config.translatorBaseUrl,
          onChanged: (v) => notifier.setField((c) => c.copyWith(translatorBaseUrl: v)),
        ),
        const SizedBox(height: 6),

        // API Key with eye toggle
        AppPasswordField(
          label: 'API Key / Authorization Token:',
          value: config.translatorApiKey,
          onChanged: (v) => notifier.setField((c) => c.copyWith(translatorApiKey: v)),
        ),
        const SizedBox(height: 6),

        // Pronoun Mode Settings
        _buildDropdownRow(
          label: 'Quy Chuẩn Xưng Hô (pronoun_mode):',
          value: ['dynamic', 'couple', 'family_parent_child', 'friends', 'formal', 'custom'].contains(config.pronounMode)
              ? config.pronounMode
              : 'dynamic',
          items: const [
            DropdownMenuItem(value: 'dynamic', child: Text('🎭 Tự động theo phân cảnh (Đa nhân vật / Phim)')),
            DropdownMenuItem(value: 'couple', child: Text('💑 Cặp đôi tình cảm (Nam: Anh - Nữ: Em)')),
            DropdownMenuItem(value: 'family_parent_child', child: Text('👨‍👩‍👧 Gia đình (Bố/Mẹ - Con)')),
            DropdownMenuItem(value: 'friends', child: Text('👥 Bạn bè thân thiết (Mình - Cậu / Bạn)')),
            DropdownMenuItem(value: 'formal', child: Text('💼 Trang trọng / Thuyết minh (Tôi - Quý vị/Anh/Chị)')),
            DropdownMenuItem(value: 'custom', child: Text('✍️ Tùy chỉnh quy tắc riêng (Custom)')),
          ],
          onChanged: (v) {
            if (v != null) notifier.setField((c) => c.copyWith(pronounMode: v));
          },
        ),
        if (config.pronounMode == 'custom') ...[
          const SizedBox(height: 6),
          _buildTextFormInput(
            label: 'Prompt Quy Tắc Xưng Hô Tùy Chỉnh:',
            hint: 'Ví dụ: Sếp xưng tôi - gọi cậu, nhân viên xưng em - gọi sếp...',
            value: config.customPronounPrompt,
            onChanged: (v) => notifier.setField((c) => c.copyWith(customPronounPrompt: v)),
          ),
        ],

        const Divider(color: AppColors.border, height: 24),

        // ── 4. NHẬN DIỆN CHỮ SUB CŨ (OCR ENGINE) ──
        _buildSectionHeader('4. NHẬN DIỆN CHỮ SUB CŨ (OCR ENGINE)'),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _buildDropdownRow(
                label: 'OCR Engine:',
                value: config.ocrEngine,
                items: const [
                  DropdownMenuItem(value: 'apple_vision', child: Text('Apple Vision (macOS Native)')),
                  DropdownMenuItem(value: 'paddle_ocr', child: Text('PaddleOCR (Python)')),
                ],
                onChanged: (v) => notifier.setField((c) => c.copyWith(ocrEngine: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownRow(
                label: 'Chế Độ OCR (mode):',
                value: config.ocrMode,
                items: const [
                  DropdownMenuItem(value: 'region', child: Text('region (Quét Dải Sub Cũ)')),
                  DropdownMenuItem(value: 'smart', child: Text('smart (Tự Động Thông Minh)')),
                  DropdownMenuItem(value: 'keyframe', child: Text('keyframe (Khung Hình Khóa)')),
                ],
                onChanged: (v) => notifier.setField((c) => c.copyWith(ocrMode: v)),
              ),
            ),
          ],
        ),

        Row(
          children: [
            Expanded(
              child: _buildTextFormInput(
                label: 'Quét Thử Nghiệm Từ (s):',
                hint: '5.0',
                value: config.detectStartSec.toString(),
                onChanged: (v) => notifier.setField((c) => c.copyWith(detectStartSec: double.tryParse(v) ?? 5.0)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextFormInput(
                label: 'Thời Lượng Thử Nghiệm (s):',
                hint: '10.0',
                value: config.detectDurationSec.toString(),
                onChanged: (v) => notifier.setField((c) => c.copyWith(detectDurationSec: double.tryParse(v) ?? 10.0)),
              ),
            ),
          ],
        ),

        const Divider(color: AppColors.border, height: 24),

        // ── 5. ĐA LUỒNG & TÀI NGUYÊN (HARDWARE CONCURRENCY) ──
        _buildSectionHeader('5. ĐA LUỒNG & TÀI NGUYÊN (HARDWARE CONCURRENCY)'),
        const SizedBox(height: 8),

        // Hardware Chip Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border, width: 0.8),
          ),
          child: Row(
            children: [
              const Icon(Icons.memory, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thiết bị: ${Platform.isMacOS ? "Apple Silicon (macOS)" : Platform.operatingSystem} • ${Platform.numberOfProcessors} CPU Cores',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Mặc định auto sẽ chọn mức trung bình chẵn (${((Platform.numberOfProcessors ~/ 2).isEven ? (Platform.numberOfProcessors ~/ 2) : (Platform.numberOfProcessors ~/ 2) - 1).clamp(2, 32)} luồng) để cân bằng tốc độ, giữ máy êm mát.',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        _buildWorkerDropdownInspector(
          label: 'Số Luồng Xử Lý Toàn Cục (app.num_workers):',
          value: config.numWorkers,
          onChanged: (v) {
            if (v != null) notifier.setField((c) => c.copyWith(numWorkers: v, ocrNumWorkers: v, ttsNumWorkers: v));
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── HELPER UI BUILDERS ────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════════════════
  // ── Compact region display + Gizmo button ──
  Widget _buildRegionEditRow({
    required String label,
    required List<double>? region,
    required FrameLayerType layerType,
    VoidCallback? onReset,
    String nullLabel = 'Tự động (Auto)',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border, width: 0.8),
                  ),
                  child: Text(
                    region != null
                        ? '${region.map((e) => (e * 100).toStringAsFixed(1)).join('%, ')}%'
                        : nullLabel,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: region != null
                          ? AppColors.primary
                          : AppColors.textMuted,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 🎯 Chỉnh Trên Video (34px)
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: AppColors.primary, width: 0.8),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.crop_free, size: 14, color: AppColors.primary),
                  label: const Text('🎯 Chỉnh',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final config = ref.read(configProvider);
                    final notifier = ref.read(configProvider.notifier);
                    if (layerType == FrameLayerType.primarySub && config.subtitleRegion == null) {
                      notifier.setField((c) => c.copyWith(
                          subtitleRegion: config.inpaintRegion != null
                              ? [...config.inpaintRegion!]
                              : [0.76, 0.05, 0.86, 0.95]));
                    } else if (layerType == FrameLayerType.secondarySub && config.subtitleSecondaryRegion == null) {
                      notifier.setField((c) => c.copyWith(
                          subtitleSecondaryRegion: [0.87, 0.05, 0.95, 0.95]));
                    } else if (layerType == FrameLayerType.inpaint && config.inpaintRegion == null) {
                      notifier.setField((c) => c.copyWith(
                          inpaintRegion: [0.75, 0.05, 0.95, 0.95]));
                    }
                    ref.read(isGizmoActiveProvider.notifier).state = true;
                    ref.read(activeGizmoLayerProvider.notifier).state = layerType;
                  },
                ),
              ),
              if (onReset != null) ...[ 
                const SizedBox(width: 6),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border, width: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: onReset,
                    child: const Text('Auto',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return AppSectionHeader(title: title);
  }

  Widget _buildToggleRow({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color activeColor = AppColors.primary,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          CompactSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = items.any((e) => e.value == value)
        ? value
        : (items.isNotEmpty ? items.first.value! : '');
    return AppDropdown<String>(
      label: label,
      value: validValue,
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildWorkerDropdownInspector({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    final totalCores = Platform.numberOfProcessors;
    final rawHalf = totalCores ~/ 2;
    final autoCores = (rawHalf.isEven ? rawHalf : rawHalf - 1).clamp(2, 32);

    final options = <String>['auto'];
    final coreSteps = [2, 4, 6, 8, 10, 12, 16, 20, 24, 32];
    for (final c in coreSteps) {
      if (c <= totalCores && !options.contains(c.toString())) {
        options.add(c.toString());
      }
    }
    if (!options.contains(totalCores.toString()) && totalCores.isEven) {
      options.add(totalCores.toString());
    }
    if (value.isNotEmpty && !options.contains(value)) {
      options.add(value);
    }

    String getOptionLabel(String opt) {
      if (opt == 'auto') {
        return 'Tự động ($autoCores luồng)';
      }
      if (opt == totalCores.toString()) {
        return '$opt luồng (Tối đa)';
      }
      return '$opt luồng';
    }

    return _buildDropdownRow(
      label: label,
      value: options.contains(value) ? value : 'auto',
      items: options.map((opt) {
        return DropdownMenuItem<String>(
          value: opt,
          child: Text(getOptionLabel(opt), overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTextFormInput({
    required String label,
    required String hint,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return AppTextField(
      key: ValueKey(label),
      label: label,
      hint: hint,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildSliderRow(String label, double val, double min, double max, Function(double) onChanged, {String Function(double)? format}) {
    return AppSliderRow(
      label: label,
      value: val,
      min: min,
      max: max,
      onChanged: onChanged,
      formatValue: format,
    );
  }

  Widget _buildVolumeRow(String label, double val, Function(double) onChanged) {
    return AppSliderRow(
      label: label,
      value: val,
      min: 0.0,
      max: 1.0,
      onChanged: onChanged,
      formatValue: (v) => '${(v * 100).toInt()}%',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ── SUBTITLE INLINE TEXT EDITOR WITH PERSISTENT CURSOR POSITION ──────────
// ═══════════════════════════════════════════════════════════════════════════
class _SubtitleInlineEditor extends StatefulWidget {
  final String text;
  final TextStyle style;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  const _SubtitleInlineEditor({
    super.key,
    required this.text,
    required this.style,
    required this.decoration,
    required this.onChanged,
  });

  @override
  State<_SubtitleInlineEditor> createState() => _SubtitleInlineEditorState();
}

class _SubtitleInlineEditorState extends State<_SubtitleInlineEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant _SubtitleInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && _controller.text != widget.text) {
      final oldSel = _controller.selection;
      _controller.text = widget.text;
      if (oldSel.start <= widget.text.length && oldSel.end <= widget.text.length) {
        _controller.selection = oldSel;
      } else {
        _controller.selection = TextSelection.collapsed(offset: widget.text.length);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      cursorColor: AppColors.primary,
      style: widget.style,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}


