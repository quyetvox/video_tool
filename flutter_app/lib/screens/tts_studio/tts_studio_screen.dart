import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/app_colors.dart';
import '../../core/file_service.dart';
import '../../core/library_filter_state.dart';
import '../../core/providers.dart';
import '../../models/video_file.dart';
import '../../widgets/asset_table_widget.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/process_logs_console_widget.dart';
import '../../widgets/resizable_collapsible_panel.dart';
import '../html_to_video/models/html_to_video_models.dart';
import 'components/components.dart';
import 'controllers/tts_studio_controller.dart';
import 'models/tts_models.dart';

class TtsStudioScreen extends ConsumerStatefulWidget {
  final ValueChanged<int>? onNavigateTab;

  const TtsStudioScreen({
    super.key,
    this.onNavigateTab,
  });

  @override
  ConsumerState<TtsStudioScreen> createState() => _TtsStudioScreenState();
}

class _TtsStudioScreenState extends ConsumerState<TtsStudioScreen> {
  late final TextEditingController _scriptCtrl;

  bool _isBottomCollapsed = false;
  bool _isPropertiesCollapsed = false;
  bool _isInspectorCollapsed = false;

  @override
  void initState() {
    super.initState();
    final initialScript = ref.read(ttsStudioProvider).rawScript;
    _scriptCtrl = TextEditingController(text: initialScript);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(ttsStudioProvider);
      if (state.rawScript.isEmpty && state.segments.isEmpty) {
        ref.read(ttsStudioProvider.notifier).loadSampleVietnameseScript();
      }
    });
  }

  @override
  void dispose() {
    _scriptCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTextFile() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Chọn tệp kịch bản thuyết minh (.txt, .md, .srt)',
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'srt'],
    );
    if (res != null && res.files.single.path != null) {
      await ref
          .read(ttsStudioProvider.notifier)
          .importScriptFile(res.files.single.path!);
    }
  }

  Future<void> _handleSaveAudioFile() async {
    final state = ref.read(ttsStudioProvider);
    final ctrl = ref.read(ttsStudioProvider.notifier);

    if (state.fullAudioPath == null || !File(state.fullAudioPath!).existsSync()) {
      final ok = await ctrl.renderFull();
      if (!ok) return;
    }

    final updatedState = ref.read(ttsStudioProvider);
    if (updatedState.fullAudioPath == null) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Lưu file âm thanh thuyết minh (.mp3)',
      fileName: 'tts_voiceover_${DateTime.now().millisecondsSinceEpoch}.mp3',
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );

    if (savePath != null && savePath.isNotEmpty) {
      final finalAudioPath = savePath.endsWith('.mp3') ? savePath : '$savePath.mp3';
      File(updatedState.fullAudioPath!).copySync(finalAudioPath);

      if (updatedState.fullSrtPath != null &&
          File(updatedState.fullSrtPath!).existsSync()) {
        final finalSrtPath = p.setExtension(finalAudioPath, '.srt');
        File(updatedState.fullSrtPath!).copySync(finalSrtPath);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('💾 Đã lưu file âm thanh & phụ đề tại: $finalAudioPath'),
            backgroundColor: AppColors.statusCompleted,
          ),
        );
      }
    }
  }

  Future<void> _sendToHtmlToMp4() async {
    final state = ref.read(ttsStudioProvider);
    final hasMaster = state.fullAudioPath != null &&
        state.fullAudioPath!.isNotEmpty &&
        File(state.fullAudioPath!).existsSync();

    if (hasMaster) {
      ref.read(htmlToVideoPresetProvider.notifier).state = HtmlToVideoPreset(
        mode: HtmlAudioSourceMode.manualAudio,
        audioPath: state.fullAudioPath,
        assPath: (state.fullSrtPath != null && File(state.fullSrtPath!).existsSync())
            ? state.fullSrtPath
            : null,
        voice: state.defaultVoice,
        durationSec: state.totalDuration > 0 ? state.totalDuration : null,
      );
    } else {
      final scriptText = state.rawScript.trim().isNotEmpty
          ? state.rawScript.trim()
          : state.segments.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join('\n');
      String? savedScriptPath;
      if (scriptText.isNotEmpty) {
        final tempFile = File(
          p.join(
            Directory.systemTemp.path,
            'tts_to_html_script_${DateTime.now().millisecondsSinceEpoch}.txt',
          ),
        );
        tempFile.writeAsStringSync(scriptText);
        savedScriptPath = tempFile.path;
      }
      ref.read(htmlToVideoPresetProvider.notifier).state = HtmlToVideoPreset(
        mode: HtmlAudioSourceMode.autoScript,
        scriptPath: savedScriptPath,
        voice: state.defaultVoice,
        durationSec: state.totalDuration > 0 ? state.totalDuration : null,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasMaster
              ? '🎬 Đã gửi Master Audio & Phụ đề sang tab HTML to MP4 Studio!'
              : '🎬 Đã gửi Kịch bản & Giọng đọc sang tab HTML to MP4 Studio!',
        ),
        backgroundColor: AppColors.statusCompleted,
        duration: const Duration(seconds: 3),
      ),
    );
    widget.onNavigateTab?.call(11);
  }

  Future<void> _sendToVideoStudio() async {
    final ctrl = ref.read(ttsStudioProvider.notifier);
    final destPath = await ctrl.exportToProjectWorkspace();
    if (destPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã lưu vào dự án: ${p.basename(destPath)}'),
          backgroundColor: AppColors.statusCompleted,
        ),
      );
      widget.onNavigateTab?.call(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final state = ref.watch(ttsStudioProvider);
    final ctrl = ref.read(ttsStudioProvider.notifier);
    final displayFiles = ref.watch(filteredProjectVideosProvider);
    final runningPaths = ref.watch(runningPathsProvider);
    final logBuffer = ref.watch(logBufferProvider);
    final isFocusMode = ref.watch(appFocusModeProvider);

    ref.listen<TtsStudioState>(ttsStudioProvider, (prev, next) {
      if (prev?.rawScript != next.rawScript && _scriptCtrl.text != next.rawScript) {
        _scriptCtrl.text = next.rawScript;
      }
    });

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          TtsHeaderBar(
            state: state,
            controller: ctrl,
            onSplitScript: () {
              ctrl.setRawScript(_scriptCtrl.text);
              ctrl.splitScript();
            },
            onRenderFull: () => ctrl.renderFull(),
            onSendToHtmlToMp4: _sendToHtmlToMp4,
            onSendToVideoStudio: _sendToVideoStudio,
          ),

          // ── BỐ CỤC 2 TẦNG ĐỒNG BỘ 1:1 CHUẨN VIDEO EDITOR ──
          Expanded(
            child: ResizableCollapsiblePanel(
              side: PanelSide.bottom,
              initialHeight: 220.0,
              minHeight: 130.0,
              maxHeight: 500.0,
              isCollapsed: isFocusMode ? true : _isBottomCollapsed,
              onCollapseChanged: (collapsed) {
                if (!isFocusMode) setState(() => _isBottomCollapsed = collapsed);
              },
              collapseTooltip: 'Thu gọn danh sách tệp & nhật ký',
              expandTooltip: 'Mở rộng danh sách tệp & nhật ký',
              panel: ResizableCollapsiblePanel(
                side: PanelSide.right,
                initialWidth: 420.0,
                minWidth: 260.0,
                maxWidth: 750.0,
                collapseTooltip: 'Thu gọn nhật ký',
                expandTooltip: 'Mở rộng nhật ký',
                panel: Container(
                  decoration: BoxDecoration(
                    color: c.surfaceDark,
                    border: Border(
                      top: BorderSide(color: c.border),
                      left: BorderSide(color: c.border),
                    ),
                  ),
                  child: ProcessLogsConsoleWidget(
                    logs: logBuffer,
                    isProcessRunning: state.isSplitting || state.isRenderingFull,
                    onClearLogs: () => ref.read(logBufferProvider.notifier).clear(),
                    onStopProcess: ctrl.stopAudio,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: AssetTableWidget(
                    files: displayFiles,
                    selectedFile: null,
                    onSelectFile: (VideoFile file) {},
                    runningRelPaths: runningPaths,
                    onRefresh: () => ref.invalidate(projectVideosProvider),
                    onOpenTrimmer: (_) {},
                    onDeleteFile: (file) async {
                      final ok = await ConfirmDialog.show(
                        context,
                        title: 'Xóa tệp?',
                        message: 'Bạn có chắc muốn xóa "${file.basename}" khỏi dự án?',
                        isDestructive: true,
                      );
                      if (ok) {
                        FileService.deleteVideoFile(file.fullPath);
                        ref.invalidate(projectVideosProvider);
                      }
                    },
                    onRenameFile: (_) {},
                  ),
                ),
              ),
              child: ResizableCollapsiblePanel(
                side: PanelSide.right,
                initialWidth: 260.0,
                minWidth: 220.0,
                maxWidth: 400.0,
                isCollapsed: isFocusMode ? true : _isPropertiesCollapsed,
                onCollapseChanged: (collapsed) {
                  if (!isFocusMode) setState(() => _isPropertiesCollapsed = collapsed);
                },
                collapseTooltip: 'Thu gọn bảng thuộc tính',
                expandTooltip: 'Mở rộng bảng thuộc tính',
                panel: TtsPropertiesInspector(
                  state: state,
                  controller: ctrl,
                  onRenderFull: () => ctrl.renderFull(),
                  onSendToHtmlToMp4: _sendToHtmlToMp4,
                  onSendToVideoStudio: _sendToVideoStudio,
                  onSaveAudioFile: _handleSaveAudioFile,
                ),
                child: ResizableCollapsiblePanel(
                  side: PanelSide.right,
                  initialWidth: 420.0,
                  minWidth: 300.0,
                  maxWidth: 680.0,
                  isCollapsed: isFocusMode ? true : _isInspectorCollapsed,
                  onCollapseChanged: (collapsed) {
                    if (!isFocusMode) setState(() => _isInspectorCollapsed = collapsed);
                  },
                  collapseTooltip: 'Thu gọn bảng kịch bản & giọng đọc',
                  expandTooltip: 'Mở rộng bảng kịch bản & giọng đọc',
                  panel: TtsInspectorPanel(
                    state: state,
                    controller: ctrl,
                    scriptCtrl: _scriptCtrl,
                    onPickTextFile: _pickTextFile,
                    onClearScript: () {
                      _scriptCtrl.clear();
                      ctrl.clearAll();
                    },
                    onSplitScript: () {
                      ctrl.setRawScript(_scriptCtrl.text);
                      ctrl.splitScript();
                    },
                  ),
                  child: TtsSegmentWorkspace(
                    state: state,
                    controller: ctrl,
                    onRenderFull: () => ctrl.renderFull(),
                    onSaveAudioFile: _handleSaveAudioFile,
                    onSendToHtmlToMp4: _sendToHtmlToMp4,
                    onSendToVideoStudio: _sendToVideoStudio,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
