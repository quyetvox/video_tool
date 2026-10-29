import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/app_colors.dart';
import '../../core/file_service.dart';
import '../../core/library_filter_state.dart';
import '../../core/providers.dart';
import '../../core/python_bridge.dart';
import '../../models/job_info.dart';
import '../../models/video_file.dart';
import '../../widgets/asset_table_widget.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/process_logs_console_widget.dart';
import '../../widgets/resizable_collapsible_panel.dart';
import '../../widgets/video_player_widget.dart';
import 'components/components.dart';
import 'models/html_to_video_models.dart';

class HtmlToVideoScreen extends ConsumerStatefulWidget {
  final ValueChanged<int>? onNavigateTab;
  const HtmlToVideoScreen({super.key, this.onNavigateTab});

  @override
  ConsumerState<HtmlToVideoScreen> createState() => _HtmlToVideoScreenState();
}

class _HtmlToVideoScreenState extends ConsumerState<HtmlToVideoScreen> {
  final _htmlPathCtrl = TextEditingController();
  final _outputPathCtrl = TextEditingController();
  final _selectorCtrl = TextEditingController(text: '#stage');
  final _durationCtrl = TextEditingController(text: '10.0');
  final _widthCtrl = TextEditingController(text: '1920');
  final _heightCtrl = TextEditingController(text: '1080');
  final _scriptPathCtrl = TextEditingController();
  final _audioPathCtrl = TextEditingController();
  final _assPathCtrl = TextEditingController();
  final _subOutlineWidthCtrl = TextEditingController(text: '3');
  final _subMarginVCtrl = TextEditingController(text: '32');
  final _secondaryFontScaleCtrl = TextEditingController(text: '0.78');
  final _playerKey = GlobalKey<VideoPlayerWidgetState>();

  String _mode = 'fullpage';
  String _selectedResPreset = '1080p Ngang (1920x1080 - YouTube/TV)';
  double _fps = 30.0;
  String _numWorkers = '0';
  String _codec = 'libx264';
  int _crf = 18;
  bool _lockTimeline = false;
  double _speechSpeed = 1.0;

  HtmlAudioSourceMode _audioSourceMode = HtmlAudioSourceMode.autoScript;
  String _voice = 'vi-VN-HoaiMyNeural';
  String _secondaryVoice = '';

  bool _burnSubtitles = true;
  bool _enableSecondarySub = false;
  String _secondaryPosition = 'above';
  String _subFont = 'Arial';
  int _subFontSize = 44;
  String _subColorHex = '#FFFFFF';
  String _subOutlineHex = '#000000';

  bool _isRunning = false;
  bool _isCompleted = false;
  double _progress = 0.0;
  String _statusMessage = 'Sẵn sàng kết xuất HTML sang MP4';
  Process? _activeProcess;

  bool _isBottomCollapsed = false;
  bool _isPropertiesCollapsed = false;
  bool _isInspectorCollapsed = false;
  bool _showVideoPlayer = false;
  String? _activePreviewVideoPath;

  @override
  void initState() {
    super.initState();
    _initDefaultDemoPaths();
  }

  void _initDefaultDemoPaths() {
    final rootDir = PythonBridge.resolveRootDir();
    final demoDir = p.join(rootDir, 'resources', '1', 'workspace', 'lecture_illustrator');
    final demoHtml = p.join(demoDir, 'demo_html_to_mp4.html');
    final demoScript = p.join(demoDir, 'demo_narration.txt');
    final demoOut = p.join(rootDir, 'resources', '1', 'output', 'demo_html_rendered.mp4');
    if (File(demoHtml).existsSync()) {
      _htmlPathCtrl.text = demoHtml;
      _outputPathCtrl.text = demoOut;
    }
    if (File(demoScript).existsSync()) _scriptPathCtrl.text = demoScript;
    if (File(demoOut).existsSync()) _activePreviewVideoPath = demoOut;
  }

  @override
  void dispose() {
    _activeProcess?.kill();
    for (final c in [
      _htmlPathCtrl, _outputPathCtrl, _selectorCtrl, _durationCtrl,
      _widthCtrl, _heightCtrl, _scriptPathCtrl, _audioPathCtrl,
      _assPathCtrl, _subOutlineWidthCtrl, _subMarginVCtrl, _secondaryFontScaleCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(HtmlToVideoPreset preset) {
    setState(() {
      _audioSourceMode = preset.mode;
      if (preset.scriptPath?.isNotEmpty == true) _scriptPathCtrl.text = preset.scriptPath!;
      if (preset.audioPath?.isNotEmpty == true) _audioPathCtrl.text = preset.audioPath!;
      if (preset.assPath?.isNotEmpty == true) _assPathCtrl.text = preset.assPath!;
      if (preset.voice != null && kHtmlVoicePresets.values.contains(preset.voice)) _voice = preset.voice!;
      if (preset.durationSec != null && preset.durationSec! > 0) {
        _durationCtrl.text = preset.durationSec!.toStringAsFixed(1);
      }
      _statusMessage = 'Đã nhận cấu hình thuyết minh từ TTS Studio!';
    });
  }

  void _pushLog(String text, {String type = 'stdout'}) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    ref.read(logBufferProvider.notifier).add(
      LogEntry(id: '${now.microsecondsSinceEpoch}', type: type, text: text, time: timeStr, jobId: 'html_to_mp4'),
    );
  }

  Future<void> _pickFileInto(TextEditingController ctrl, String title, List<String> exts, {bool autoOut = false}) async {
    final res = await FilePicker.platform.pickFiles(dialogTitle: title, type: FileType.custom, allowedExtensions: exts);
    if (res != null && res.files.single.path != null) {
      final path = res.files.single.path!;
      setState(() {
        ctrl.text = path;
        if (autoOut) {
          final stem = p.basenameWithoutExtension(path);
          final activeProj = ref.read(activeProjectProvider) ?? '1';
          _outputPathCtrl.text = p.join(ref.read(projectsDirProvider), activeProj, 'output', '${stem}_rendered.mp4');
        }
      });
    }
  }

  Future<void> _pickOutputPath() async {
    final res = await FilePicker.platform.saveFile(
      dialogTitle: 'Chọn đường dẫn lưu file MP4',
      fileName: _outputPathCtrl.text.isNotEmpty ? p.basename(_outputPathCtrl.text) : 'html_video.mp4',
      type: FileType.custom,
      allowedExtensions: ['mp4'],
    );
    if (res != null && res.isNotEmpty) {
      setState(() => _outputPathCtrl.text = res.endsWith('.mp4') ? res : '$res.mp4');
    }
  }

  Future<void> _startRender() async {
    final htmlPath = _htmlPathCtrl.text.trim();
    final outPath = _outputPathCtrl.text.trim();
    if (htmlPath.isEmpty || !File(htmlPath).existsSync()) {
      _pushLog('❌ Vui lòng chọn file .html hợp lệ!', type: 'system-error');
      return;
    }
    if (outPath.isEmpty) {
      _pushLog('❌ Vui lòng nhập đường dẫn lưu file .mp4!', type: 'system-error');
      return;
    }

    setState(() {
      _isRunning = true;
      _isCompleted = false;
      _progress = 0.02;
      _statusMessage = 'Đang khởi chạy trình duyệt & chuẩn bị kết xuất...';
    });

    final rootDir = PythonBridge.resolveRootDir();
    final pythonBin = PythonBridge.resolvePythonBin();
    final scriptFile = p.join(rootDir, 'py_engine', 'engine', 'features', 'render', 'html_to_mp4.py');
    final wStr = _widthCtrl.text.trim().isEmpty ? '1920' : _widthCtrl.text.trim();
    final hStr = _heightCtrl.text.trim().isEmpty ? '1080' : _heightCtrl.text.trim();

    final args = <String>[
      scriptFile, htmlPath, '-o', outPath, '--res', '${wStr}x$hStr',
      '--fps', '${_fps.toInt()}', '--num-workers', _numWorkers == '0' ? 'auto' : _numWorkers,
    ];

    final dur = double.tryParse(_durationCtrl.text.trim());
    if (dur != null && dur > 0) args.addAll(['-d', dur.toString()]);

    if (_audioSourceMode == HtmlAudioSourceMode.manualAudio && _audioPathCtrl.text.trim().isNotEmpty) {
      args.addAll(['-a', _audioPathCtrl.text.trim()]);
    }

    if (_burnSubtitles) {
      args.add('--burn-subtitles');
      if (_audioSourceMode == HtmlAudioSourceMode.manualAudio && _assPathCtrl.text.trim().isNotEmpty) {
        args.addAll(['-s', _assPathCtrl.text.trim()]);
      }
      if (_enableSecondarySub) args.addAll(['--secondary-lang', 'vi', '--secondary-font-size', '30']);
    } else {
      args.add('--no-subtitles');
    }

    if (_audioSourceMode == HtmlAudioSourceMode.autoScript && _scriptPathCtrl.text.trim().isNotEmpty) {
      args.addAll(['--script', _scriptPathCtrl.text.trim()]);
    }
    final isViVoice = _voice.startsWith('vi') || _voice == 'gtts_vi';
    args.addAll([
      '--voice', _voice, '--speed', _speechSpeed.toStringAsFixed(2),
      '--lang', isViVoice ? 'vi' : 'en', '--font-size', '$_subFontSize',
      _lockTimeline ? '--lock-timeline' : '--no-lock-timeline',
    ]);

    _pushLog('🚀 Bắt đầu kết xuất HTML sang MP4: ${p.basename(htmlPath)} → ${p.basename(outPath)}', type: 'system-info');

    try {
      final env = Map<String, String>.from(Platform.environment)
        ..['PYTHONPATH'] = p.join(rootDir, 'py_engine')
        ..['PYTHONIOENCODING'] = 'utf-8';

      final proc = await Process.start(pythonBin, args, workingDirectory: rootDir, environment: env);
      _activeProcess = proc;

      proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_handleEngineLine);
      proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => _handleEngineLine(l, isErr: true));

      final code = await proc.exitCode;
      if (!mounted) return;
      _activeProcess = null;

      if (code == 0 && File(outPath).existsSync()) {
        setState(() {
          _isRunning = false;
          _isCompleted = true;
          _progress = 1.0;
          _statusMessage = 'Hoàn tất xuất MP4: ${p.basename(outPath)}';
          _activePreviewVideoPath = outPath;
          _showVideoPlayer = true;
        });
        _pushLog('🎉 Kết xuất thành công: $outPath', type: 'system-success');
        ref.invalidate(projectVideosProvider);
      } else {
        setState(() {
          _isRunning = false;
          _statusMessage = 'Quá trình kết xuất dừng (Mã thoát: $code)';
        });
        _pushLog('❌ Tiến trình kết thúc với mã lỗi $code', type: 'system-error');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _statusMessage = 'Lỗi khởi chạy: $e';
      });
      _pushLog('❌ Ngoại lệ khi chạy html_to_mp4: $e', type: 'system-error');
    }
  }

  void _handleEngineLine(String line, {bool isErr = false}) {
    if (!mounted || line.trim().isEmpty) return;
    final pctMatch = RegExp(r'\((\d+(?:\.\d+)?)%\)').firstMatch(line);
    setState(() {
      if (pctMatch != null) {
        final pct = double.tryParse(pctMatch.group(1)!) ?? 0.0;
        _progress = (pct / 100.0).clamp(0.02, 0.99);
        _statusMessage = line.trim();
      } else if (line.contains('Đang tạo giọng đọc') || line.contains('Bắt đầu chụp') || line.contains('Phân chia') || line.contains('Hoàn tất')) {
        _statusMessage = line.trim();
      }
    });
    _pushLog(line, type: isErr ? 'stderr' : 'stdout');
  }

  void _stopRender() {
    _activeProcess?.kill();
    _activeProcess = null;
    setState(() {
      _isRunning = false;
      _statusMessage = 'Đã hủy tiến trình kết xuất.';
    });
    _pushLog('🛑 Đã dừng tiến trình kết xuất theo yêu cầu.', type: 'system-info');
  }

  void _openPathInSystem(String targetPath, {bool revealFolder = false}) {
    if (targetPath.isEmpty) return;
    if (Platform.isMacOS) {
      Process.run('open', revealFolder ? ['-R', targetPath] : [targetPath]);
    } else if (Platform.isWindows) {
      Process.run('explorer', revealFolder ? ['/select,', targetPath] : [targetPath]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final displayFiles = ref.watch(filteredProjectVideosProvider);
    final runningPaths = ref.watch(runningPathsProvider);
    final logBuffer = ref.watch(logBufferProvider);
    final isFocusMode = ref.watch(appFocusModeProvider);

    ref.listen<HtmlToVideoPreset?>(htmlToVideoPresetProvider, (prev, next) {
      if (next != null) {
        _applyPreset(next);
        Future.microtask(() => ref.read(htmlToVideoPresetProvider.notifier).state = null);
      }
    });

    VideoFile? selectedVideo;
    if (_activePreviewVideoPath != null && _activePreviewVideoPath!.isNotEmpty) {
      for (final f in displayFiles) {
        if (f.fullPath == _activePreviewVideoPath) {
          selectedVideo = f;
          break;
        }
      }
    }

    final width = int.tryParse(_widthCtrl.text.trim()) ?? 1920;
    final height = int.tryParse(_heightCtrl.text.trim()) ?? 1080;
    void pickHtml() => _pickFileInto(_htmlPathCtrl, 'Chọn file HTML cần chuyển sang MP4', ['html', 'htm'], autoOut: true);

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          HtmlHeaderBar(
            htmlPath: _htmlPathCtrl.text, outputPath: _outputPathCtrl.text,
            width: width, height: height, fps: _fps, numWorkers: _numWorkers,
            isRunning: _isRunning, isCompleted: _isCompleted, progress: _progress, statusMessage: _statusMessage,
            onPickHtml: pickHtml, onStartRender: _startRender, onStopRender: _stopRender,
            onOpenOutputFolder: () => _openPathInSystem(_outputPathCtrl.text.trim(), revealFolder: true),
            onSwitchToTtsStudio: widget.onNavigateTab != null ? () => widget.onNavigateTab!(10) : null,
          ),
          Expanded(
            child: ResizableCollapsiblePanel(
              side: PanelSide.bottom, initialHeight: 220.0, minHeight: 130.0, maxHeight: 500.0,
              isCollapsed: isFocusMode ? true : _isBottomCollapsed,
              onCollapseChanged: (col) => !isFocusMode ? setState(() => _isBottomCollapsed = col) : null,
              collapseTooltip: 'Thu gọn danh sách video & nhật ký', expandTooltip: 'Mở rộng danh sách video & nhật ký',
              panel: ResizableCollapsiblePanel(
                side: PanelSide.right, initialWidth: 420.0, minWidth: 260.0, maxWidth: 750.0,
                collapseTooltip: 'Thu gọn nhật ký', expandTooltip: 'Mở rộng nhật ký',
                panel: Container(
                  decoration: BoxDecoration(color: c.surfaceDark, border: Border(top: BorderSide(color: c.border), left: BorderSide(color: c.border))),
                  child: ProcessLogsConsoleWidget(
                    logs: logBuffer, isProcessRunning: _isRunning,
                    onClearLogs: () => ref.read(logBufferProvider.notifier).clear(), onStopProcess: _stopRender,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
                  child: AssetTableWidget(
                    files: displayFiles, selectedFile: selectedVideo,
                    onSelectFile: (file) => setState(() {
                      _activePreviewVideoPath = file.fullPath;
                      _showVideoPlayer = true;
                    }),
                    runningRelPaths: runningPaths, onRefresh: () => ref.invalidate(projectVideosProvider), onOpenTrimmer: (_) {},
                    onDeleteFile: (file) async {
                      final ok = await ConfirmDialog.show(context, title: 'Xóa video?', message: 'Bạn có chắc muốn xóa "${file.basename}" khỏi dự án?', isDestructive: true);
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
                side: PanelSide.right, initialWidth: 270.0, minWidth: 220.0, maxWidth: 420.0,
                isCollapsed: isFocusMode ? true : _isPropertiesCollapsed,
                onCollapseChanged: (col) => !isFocusMode ? setState(() => _isPropertiesCollapsed = col) : null,
                collapseTooltip: 'Thu gọn bảng thuộc tính', expandTooltip: 'Mở rộng bảng thuộc tính',
                panel: HtmlPropertiesInspector(
                  htmlPath: _htmlPathCtrl.text, outputPath: _outputPathCtrl.text, width: width, height: height, fps: _fps,
                  durationStr: _durationCtrl.text, numWorkers: _numWorkers, codec: _codec, audioSourceMode: _audioSourceMode,
                  scriptPath: _scriptPathCtrl.text, audioPath: _audioPathCtrl.text, burnSubtitles: _burnSubtitles,
                  isRunning: _isRunning, isCompleted: _isCompleted, onStartRender: _startRender,
                  onOpenOutputFile: () => _openPathInSystem(_outputPathCtrl.text.trim()),
                  onOpenOutputFolder: () => _openPathInSystem(_outputPathCtrl.text.trim(), revealFolder: true),
                ),
                child: ResizableCollapsiblePanel(
                  side: PanelSide.right, initialWidth: 430.0, minWidth: 300.0, maxWidth: 700.0,
                  isCollapsed: isFocusMode ? true : _isInspectorCollapsed,
                  onCollapseChanged: (col) => !isFocusMode ? setState(() => _isInspectorCollapsed = col) : null,
                  collapseTooltip: 'Thu gọn bảng cấu hình HTML & Giọng đọc', expandTooltip: 'Mở rộng bảng cấu hình HTML & Giọng đọc',
                  panel: HtmlInspectorPanel(
                    htmlPathCtrl: _htmlPathCtrl, outputPathCtrl: _outputPathCtrl, selectorCtrl: _selectorCtrl,
                    durationCtrl: _durationCtrl, widthCtrl: _widthCtrl, heightCtrl: _heightCtrl,
                    scriptPathCtrl: _scriptPathCtrl, audioPathCtrl: _audioPathCtrl, assPathCtrl: _assPathCtrl,
                    subOutlineWidthCtrl: _subOutlineWidthCtrl, subMarginVCtrl: _subMarginVCtrl, secondaryFontScaleCtrl: _secondaryFontScaleCtrl,
                    mode: _mode, onModeChanged: (v) => setState(() => _mode = v),
                    selectedResPreset: _selectedResPreset,
                    onResPresetChanged: (v) {
                      final dims = kHtmlResolutionPresets[v];
                      setState(() {
                        _selectedResPreset = v;
                        if (dims != null) {
                          _widthCtrl.text = dims[0].toString();
                          _heightCtrl.text = dims[1].toString();
                        }
                      });
                    },
                    onCustomDimensionChanged: () => setState(() => _selectedResPreset = 'Tùy chỉnh (Custom)'),
                    fps: _fps, onFpsChanged: (v) => setState(() => _fps = v),
                    numWorkers: _numWorkers, onNumWorkersChanged: (v) => setState(() => _numWorkers = v),
                    codec: _codec, onCodecChanged: (v) => setState(() => _codec = v),
                    crf: _crf, onCrfChanged: (v) => setState(() => _crf = v),
                    lockTimeline: _lockTimeline, onLockTimelineChanged: (v) => setState(() => _lockTimeline = v),
                    speechSpeed: _speechSpeed, onSpeechSpeedChanged: (v) => setState(() => _speechSpeed = v),
                    audioSourceMode: _audioSourceMode, onAudioSourceModeChanged: (v) => setState(() => _audioSourceMode = v),
                    voice: _voice, onVoiceChanged: (v) => setState(() => _voice = v),
                    secondaryVoice: _secondaryVoice, onSecondaryVoiceChanged: (v) => setState(() => _secondaryVoice = v),
                    burnSubtitles: _burnSubtitles, onBurnSubtitlesChanged: (v) => setState(() => _burnSubtitles = v),
                    enableSecondarySub: _enableSecondarySub, onEnableSecondarySubChanged: (v) => setState(() => _enableSecondarySub = v),
                    secondaryPosition: _secondaryPosition, onSecondaryPositionChanged: (v) => setState(() => _secondaryPosition = v),
                    subFont: _subFont, onSubFontChanged: (v) => setState(() => _subFont = v),
                    subFontSize: _subFontSize, onSubFontSizeChanged: (v) => setState(() => _subFontSize = v),
                    subColorHex: _subColorHex, onSubColorHexChanged: (v) => setState(() => _subColorHex = v),
                    subOutlineHex: _subOutlineHex, onSubOutlineHexChanged: (v) => setState(() => _subOutlineHex = v),
                    onPickHtml: pickHtml, onPickOutput: _pickOutputPath,
                    onPickScript: () => _pickFileInto(_scriptPathCtrl, 'Chọn file kịch bản (.txt, .md)', ['txt', 'md']),
                    onClearScript: () => setState(() => _scriptPathCtrl.clear()),
                    onPickAudio: () => _pickFileInto(_audioPathCtrl, 'Chọn file âm thanh (.mp3, .wav, .m4a)', ['mp3', 'wav', 'm4a', 'aac']),
                    onClearAudio: () => setState(() => _audioPathCtrl.clear()),
                    onPickAss: () => _pickFileInto(_assPathCtrl, 'Chọn file phụ đề (.ass, .srt)', ['ass', 'srt']),
                    onClearAss: () => setState(() => _assPathCtrl.clear()),
                    onOpenTtsStudio: widget.onNavigateTab != null ? () => widget.onNavigateTab!(10) : null,
                  ),
                  child: HtmlVideoHeroCanvas(
                    htmlPath: _htmlPathCtrl.text, outputPath: _outputPathCtrl.text,
                    activePreviewVideoPath: _activePreviewVideoPath, showVideoPlayer: _showVideoPlayer,
                    onTogglePreviewMode: (showVideo) => setState(() => _showVideoPlayer = showVideo),
                    audioSourceMode: _audioSourceMode, scriptPath: _scriptPathCtrl.text,
                    audioPath: _audioPathCtrl.text, assPath: _assPathCtrl.text, voice: _voice,
                    width: width, height: height, fps: _fps, durationStr: _durationCtrl.text,
                    numWorkers: _numWorkers, burnSubtitles: _burnSubtitles,
                    isRunning: _isRunning, isCompleted: _isCompleted, progress: _progress, statusMessage: _statusMessage,
                    playerKey: _playerKey,
                    onToggleFullscreen: () => ref.read(appFocusModeProvider.notifier).state = !isFocusMode,
                    onPickHtml: pickHtml,
                    onOpenHtmlInBrowser: () => _openPathInSystem(_htmlPathCtrl.text.trim()),
                    onOpenOutputFile: () => _openPathInSystem(_outputPathCtrl.text.trim()),
                    onOpenOutputFolder: () => _openPathInSystem(_outputPathCtrl.text.trim(), revealFolder: true),
                    onStartRender: _startRender,
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
