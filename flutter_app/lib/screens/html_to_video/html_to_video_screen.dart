import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../core/app_colors.dart';
import '../../core/providers.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/tool_header_toolbar.dart';

class HtmlToVideoScreen extends ConsumerStatefulWidget {
  const HtmlToVideoScreen({super.key});

  @override
  ConsumerState<HtmlToVideoScreen> createState() => _HtmlToVideoScreenState();
}

class _HtmlToVideoScreenState extends ConsumerState<HtmlToVideoScreen> {
  final _htmlPathController = TextEditingController();
  final _outputPathController = TextEditingController();
  final _durationController = TextEditingController();
  final _audioPathController = TextEditingController();
  final _subtitlePathController = TextEditingController();
  final _scriptPathController = TextEditingController();

  String _selectedRes = '1920x1080';
  int _selectedFps = 24;
  String _numWorkers = 'auto';

  // TTS & Subtitle configurations
  String _selectedLang = 'en';
  String _selectedVoice = 'en-US-JennyNeural';
  double _speechSpeed = 1.0;
  bool _lockTimeline = false;
  bool _burnSubtitles = true;
  int _subtitleFontSize = 36;
  bool _enableSecondarySubtitles = false;
  String _selectedSecondaryLang = 'vi';
  int _secondaryFontSize = 26;

  final Map<String, String> _languages = const {
    'en': 'English (en)',
    'vi': 'Tiếng Việt (vi)',
    'zh': 'Chinese (zh)',
    'ja': 'Japanese (ja)',
  };

  final Map<String, String> _secondaryLanguages = const {
    'vi': 'Tiếng Việt (vi)',
    'en': 'English (en)',
    'zh': 'Chinese (zh)',
    'ja': 'Japanese (ja)',
    'ko': 'Korean (ko)',
    'fr': 'French (fr)',
  };

  final Map<String, List<Map<String, String>>> _voicesByLang = const {
    'en': [
      {'name': 'en-US-JennyNeural (Nữ Mỹ)', 'value': 'en-US-JennyNeural'},
      {'name': 'en-US-GuyNeural (Nam Mỹ)', 'value': 'en-US-GuyNeural'},
      {'name': 'en-GB-SoniaNeural (Nữ Anh)', 'value': 'en-GB-SoniaNeural'},
      {'name': 'en-GB-RyanNeural (Nam Anh)', 'value': 'en-GB-RyanNeural'},
    ],
    'vi': [
      {'name': 'vi-VN-BanMai (Ban Mai - Nữ nhẹ nhàng)', 'value': 'vi-VN-BanMai'},
      {'name': 'vi-VN-HoaiMyNeural (Hoài My - Nữ Bắc)', 'value': 'vi-VN-HoaiMyNeural'},
      {'name': 'vi-VN-NamMinhNeural (Nam Minh - Nam Bắc)', 'value': 'vi-VN-NamMinhNeural'},
    ],
    'zh': [
      {'name': 'zh-CN-XiaoxiaoNeural (Nữ)', 'value': 'zh-CN-XiaoxiaoNeural'},
      {'name': 'zh-CN-YunxiNeural (Nam)', 'value': 'zh-CN-YunxiNeural'},
    ],
    'ja': [
      {'name': 'ja-JP-NanamiNeural (Nữ)', 'value': 'ja-JP-NanamiNeural'},
      {'name': 'ja-JP-KeitaNeural (Nam)', 'value': 'ja-JP-KeitaNeural'},
    ],
  };

  bool _isConverting = false;
  double _progress = 0.0;
  String _statusText = 'Sẵn sàng';
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  Process? _activeProcess;

  @override
  void dispose() {
    _htmlPathController.dispose();
    _outputPathController.dispose();
    _durationController.dispose();
    _audioPathController.dispose();
    _subtitlePathController.dispose();
    _scriptPathController.dispose();
    _logScrollController.dispose();
    _activeProcess?.kill();
    super.dispose();
  }

  void _addLog(String msg) {
    setState(() {
      _logs.add(msg);
      if (_logs.length > 500) _logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickHtmlFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm', 'svg'],
    );
    if (res != null && res.files.single.path != null) {
      final selected = res.files.single.path!;
      _htmlPathController.text = selected;
      if (_outputPathController.text.isEmpty) {
        final dir = p.dirname(selected);
        final stem = p.basenameWithoutExtension(selected);
        _outputPathController.text = p.join(dir, '$stem.mp4');
      }
      setState(() {});
    }
  }

  Future<void> _pickAudioFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a', 'aac'],
    );
    if (res != null && res.files.single.path != null) {
      _audioPathController.text = res.files.single.path!;
      setState(() {});
    }
  }

  Future<void> _pickSubtitleFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ass', 'srt'],
    );
    if (res != null && res.files.single.path != null) {
      _subtitlePathController.text = res.files.single.path!;
      setState(() {});
    }
  }

  Future<void> _pickScriptFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md'],
    );
    if (res != null && res.files.single.path != null) {
      _scriptPathController.text = res.files.single.path!;
      setState(() {});
    }
  }

  Future<void> _startConversion() async {
    final htmlPath = _htmlPathController.text.trim();
    if (htmlPath.isEmpty || !File(htmlPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Vui lòng chọn file HTML nguồn hợp lệ.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final outPath = _outputPathController.text.trim().isNotEmpty
        ? _outputPathController.text.trim()
        : p.join(p.dirname(htmlPath), '${p.basenameWithoutExtension(htmlPath)}.mp4');

    setState(() {
      _isConverting = true;
      _progress = 0.0;
      _statusText = 'Đang khởi chạy Playwright & FFmpeg...';
      _logs.clear();
    });

    _addLog('🚀 Bắt đầu chuyển đổi HTML sang MP4: $htmlPath');
    _addLog('📍 File đích: $outPath');
    _addLog('⚙️ Cấu hình: Res=$_selectedRes, FPS=$_selectedFps, Workers=$_numWorkers');

    final projectsDir = ref.read(projectsDirProvider);
    final pythonBin = Platform.isWindows
        ? p.join(projectsDir, '..', '.venv', 'Scripts', 'python.exe')
        : p.join(projectsDir, '..', '.venv', 'bin', 'python');

    final actualPython = File(pythonBin).existsSync() ? pythonBin : 'python3';
    final scriptPath = p.join(projectsDir, '..', 'py_engine', 'html_to_mp4.py');

    final args = [
      scriptPath,
      htmlPath,
      '-o', outPath,
      '--res', _selectedRes,
      '--fps', '$_selectedFps',
    ];

    if (_durationController.text.trim().isNotEmpty) {
      final dur = double.tryParse(_durationController.text.trim());
      if (dur != null && dur > 0) {
        args.addAll(['-d', dur.toString()]);
      }
    }

    if (_audioPathController.text.trim().isNotEmpty) {
      args.addAll(['-a', _audioPathController.text.trim()]);
    }

    if (_burnSubtitles) {
      args.add('--burn-subtitles');
      if (_subtitlePathController.text.trim().isNotEmpty) {
        args.addAll(['-s', _subtitlePathController.text.trim()]);
      }
      if (_enableSecondarySubtitles) {
        args.addAll(['--secondary-lang', _selectedSecondaryLang]);
        args.addAll(['--secondary-font-size', '$_secondaryFontSize']);
      }
    } else {
      args.add('--no-subtitles');
    }

    if (_scriptPathController.text.trim().isNotEmpty) {
      args.addAll(['--script', _scriptPathController.text.trim()]);
    }
    args.addAll(['--voice', _selectedVoice]);
    args.addAll(['--speed', _speechSpeed.toStringAsFixed(2)]);
    args.addAll(['--lang', _selectedLang]);
    args.addAll(['--font-size', '$_subtitleFontSize']);
    if (_lockTimeline) {
      args.add('--lock-timeline');
    } else {
      args.add('--no-lock-timeline');
    }

    try {
      final proc = await Process.start(actualPython, args);
      _activeProcess = proc;

      proc.stdout.transform(utf8.decoder).listen((data) {
        final lines = data.split(RegExp(r'[\r\n]+'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          _addLog(trimmed);

          // Parse percent
          final match = RegExp(r'\((\d+(?:\.\d+)?)%\)').firstMatch(trimmed);
          if (match != null) {
            final pct = double.tryParse(match.group(1) ?? '0') ?? 0.0;
            setState(() {
              _progress = (pct / 100.0).clamp(0.0, 1.0);
              _statusText = 'Đang render: ${pct.toStringAsFixed(1)}%';
            });
          }
        }
      });

      proc.stderr.transform(utf8.decoder).listen((data) {
        final trimmed = data.trim();
        if (trimmed.isNotEmpty) {
          _addLog('⚠️ $trimmed');
        }
      });

      final exitCode = await proc.exitCode;
      _activeProcess = null;

      if (exitCode == 0) {
        setState(() {
          _isConverting = false;
          _progress = 1.0;
          _statusText = '✅ Chuyển đổi thành công 100%!';
        });
        _addLog('🎉 Hoàn tất xuất video tại: $outPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Đã xuất video thành công: ${p.basename(outPath)}'),
              backgroundColor: AppColors.statusCompleted,
            ),
          );
        }
      } else {
        setState(() {
          _isConverting = false;
          _statusText = '❌ Thất bại (Mã lỗi: $exitCode)';
        });
        _addLog('❌ Lỗi tiến trình chuyển đổi (Mã lỗi: $exitCode)');
      }
    } catch (e) {
      _activeProcess = null;
      setState(() {
        _isConverting = false;
        _statusText = '❌ Ngoại lệ: $e';
      });
      _addLog('❌ Ngoại lệ: $e');
    }
  }

  void _cancelConversion() {
    if (_activeProcess != null) {
      _activeProcess!.kill();
      _activeProcess = null;
      setState(() {
        _isConverting = false;
        _statusText = 'Đã dừng chuyển đổi bởi người dùng.';
      });
      _addLog('🛑 Đã dừng tiến trình.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header Toolbar
          ToolHeaderToolbar(
            title: 'HTML sang Video MP4 Studio',
            breadcrumb: 'Chuyển đổi kịch bản HTML/SVG hoạt họa sang MP4 tăng tốc phần cứng',
            icon: const Icon(Icons.html, color: AppColors.primary, size: 18),
            actions: [
              if (_isConverting)
                AppButton(
                  label: 'Hủy Tiến Trình',
                  icon: Icons.stop_circle_outlined,
                  variant: AppButtonVariant.danger,
                  onPressed: _cancelConversion,
                )
              else
                AppButton(
                  label: 'Bắt Đầu Render MP4',
                  icon: Icons.movie_creation_outlined,
                  variant: AppButtonVariant.primary,
                  onPressed: _startConversion,
                ),
            ],
          ),

          // Main Body
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Configuration Column (55%)
                Expanded(
                  flex: 55,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildCard(
                        title: '1. File Nguồn & Đích (Source & Target)',
                        icon: Icons.file_present_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInputRow(
                              label: 'File HTML / SVG nguồn:',
                              controller: _htmlPathController,
                              hint: 'Chọn file .html hoạt họa bài giảng hoặc kịch bản web...',
                              onPick: _pickHtmlFile,
                            ),
                            const SizedBox(height: 12),
                            _buildInputRow(
                              label: 'Đường dẫn file MP4 xuất:',
                              controller: _outputPathController,
                              hint: 'Tự động theo tên file nguồn nếu để trống...',
                              onPick: () async {
                                final res = await FilePicker.platform.saveFile(
                                  dialogTitle: 'Chọn nơi lưu file MP4',
                                  fileName: 'output.mp4',
                                  type: FileType.custom,
                                  allowedExtensions: ['mp4'],
                                );
                                if (res != null) {
                                  _outputPathController.text = res;
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        title: '2. Thông Số Video & Tăng Tốc Phần Cứng',
                        icon: Icons.tune,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDropdown(
                                    label: 'Độ phân giải (Resolution):',
                                    value: _selectedRes,
                                    items: const ['1920x1080', '1080x1920', '1080x1080', '1280x720'],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedRes = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildDropdown(
                                    label: 'Tốc độ khung hình (FPS):',
                                    value: '$_selectedFps FPS',
                                    items: const ['24 FPS', '30 FPS', '60 FPS'],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedFps = int.parse(val.split(' ')[0]));
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Thời lượng (giây - để trống để tự động dò):',
                                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _durationController,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 13, color: Colors.white),
                                        onChanged: (val) {
                                          if (val.trim().isNotEmpty && !_lockTimeline) {
                                            setState(() => _lockTimeline = true);
                                          }
                                        },
                                        decoration: InputDecoration(
                                          hintText: 'Tự động lấy theo metadata HTML/Audio...',
                                          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                          filled: true,
                                          fillColor: AppColors.surfaceLight,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            borderSide: const BorderSide(color: AppColors.border),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildDropdown(
                                    label: 'Đa luồng xử lý (num_workers):',
                                    value: _numWorkers,
                                    items: const ['auto', '1', '2', '4', '8'],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _numWorkers = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        title: '3. Âm Thanh & Phụ Đề Kèm Theo (Tùy Chọn)',
                        icon: Icons.audiotrack_outlined,
                        child: Column(
                          children: [
                            _buildInputRow(
                              label: 'File Audio thuyết minh (.wav, .mp3):',
                              controller: _audioPathController,
                              hint: 'Ghép trực tiếp âm thanh vào MP4 trong 1-Pass...',
                              onPick: _pickAudioFile,
                            ),
                            const SizedBox(height: 12),
                            _buildInputRow(
                              label: 'File Phụ đề (.ass, .srt):',
                              controller: _subtitlePathController,
                              hint: 'Burn phụ đề cứng ASS sắc nét vào video...',
                              onPick: _pickSubtitleFile,
                            ),
                            const SizedBox(height: 12),
                            _buildInputRow(
                              label: 'Kịch bản thuyết minh (.txt, .md):',
                              controller: _scriptPathController,
                              hint: 'Tự động tạo audio TTS và phụ đề khớp timeline video...',
                              onPick: _pickScriptFile,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        title: '4. Cấu Hình Giọng Đọc AI (TTS Settings)',
                        icon: Icons.record_voice_over_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildKeyValueDropdown(
                                    label: 'Ngôn ngữ thuyết minh:',
                                    value: _selectedLang,
                                    items: _languages.entries
                                        .map((e) => {'name': e.value, 'value': e.key})
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedLang = val;
                                          final list = _voicesByLang[val];
                                          if (list != null && list.isNotEmpty) {
                                            _selectedVoice = list.first['value']!;
                                          }
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _buildKeyValueDropdown(
                                    label: 'Giọng đọc AI (Voice):',
                                    value: _selectedVoice,
                                    items: _voicesByLang[_selectedLang] ?? [],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedVoice = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Tốc độ đọc (Speech Speed):',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    '${_speechSpeed.toStringAsFixed(2)}x',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.surfaceLight,
                                thumbColor: AppColors.primary,
                                overlayColor: AppColors.primary.withOpacity(0.2),
                                trackHeight: 3,
                              ),
                              child: Slider(
                                value: _speechSpeed,
                                min: 0.75,
                                max: 1.50,
                                divisions: 15,
                                onChanged: (val) => setState(() => _speechSpeed = val),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Row(
                                children: [
                                  Text(
                                    'Khóa Timeline (Timeline Lock)',
                                    style: TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.lock_clock_outlined, size: 14, color: AppColors.primary),
                                ],
                              ),
                              subtitle: Text(
                                _lockTimeline
                                    ? 'Bật: Khóa đúng mốc slot [start - end], tự động tăng tốc nếu chữ dài, giữ sàn ${_speechSpeed.toStringAsFixed(2)}x'
                                    : 'Tắt (Auto): Audio làm chuẩn thời gian (Master), animation tự co giãn khớp 100% giọng đọc',
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                              value: _lockTimeline,
                              activeColor: AppColors.primary,
                              onChanged: (val) => setState(() => _lockTimeline = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCard(
                        title: '5. Tùy Chọn Phụ Đề & Hiển Thị (Subtitle Settings)',
                        icon: Icons.subtitles_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Nhúng phụ đề cứng (Burn Subtitles)',
                                      style: TextStyle(fontSize: 12.5, color: Colors.white),
                                    ),
                                    subtitle: const Text(
                                      'Tự động render phụ đề ASS sắc nét vào từng khung hình',
                                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                    ),
                                    value: _burnSubtitles,
                                    activeColor: AppColors.primary,
                                    onChanged: (val) => setState(() => _burnSubtitles = val),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                SizedBox(
                                  width: 140,
                                  child: _buildDropdown(
                                    label: 'Kích cỡ chữ chính:',
                                    value: '$_subtitleFontSize pt',
                                    items: const ['24 pt', '28 pt', '32 pt', '36 pt', '40 pt', '48 pt'],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _subtitleFontSize = int.parse(val.split(' ')[0]));
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if (_burnSubtitles) ...[
                              const Divider(height: 20, color: AppColors.border),
                              Row(
                                children: [
                                  Expanded(
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Bật phụ đề phụ / song ngữ (Secondary Subtitles)',
                                        style: TextStyle(fontSize: 12.5, color: Colors.white),
                                      ),
                                      subtitle: const Text(
                                        'Hiển thị dòng dịch thứ 2 (màu vàng nổi bật bên dưới)',
                                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                                      ),
                                      value: _enableSecondarySubtitles,
                                      activeColor: AppColors.primary,
                                      onChanged: (val) => setState(() => _enableSecondarySubtitles = val),
                                    ),
                                  ),
                                  if (_enableSecondarySubtitles) ...[
                                    const SizedBox(width: 14),
                                    SizedBox(
                                      width: 150,
                                      child: _buildKeyValueDropdown(
                                        label: 'Ngôn ngữ phụ:',
                                        value: _selectedSecondaryLang,
                                        items: _secondaryLanguages.entries
                                            .map((e) => {'name': e.value, 'value': e.key})
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) setState(() => _selectedSecondaryLang = val);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 120,
                                      child: _buildDropdown(
                                        label: 'Cỡ chữ phụ:',
                                        value: '$_secondaryFontSize pt',
                                        items: const ['18 pt', '22 pt', '26 pt', '30 pt', '34 pt'],
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _secondaryFontSize = int.parse(val.split(' ')[0]));
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Monitor & Log Column (45%)
                Expanded(
                  flex: 45,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Progress bar header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _isConverting ? Icons.sync : Icons.terminal,
                                        size: 18,
                                        color: _isConverting ? AppColors.primary : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Tiến Trình & Nhật Ký Render',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${(_progress * 100).toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _isConverting ? AppColors.primary : AppColors.statusCompleted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _progress,
                                  minHeight: 8,
                                  backgroundColor: AppColors.surfaceLight,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _progress >= 1.0 ? AppColors.statusCompleted : AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _statusText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Terminal Log Console
                        Expanded(
                          child: Container(
                            color: const Color(0xFF090D16),
                            padding: const EdgeInsets.all(12),
                            child: ListView.builder(
                              controller: _logScrollController,
                              itemCount: _logs.length,
                              itemBuilder: (ctx, i) {
                                final log = _logs[i];
                                Color col = const Color(0xFFCBD5E1);
                                if (log.startsWith('🚀') || log.startsWith('⚙️')) {
                                  col = const Color(0xFF60A5FA);
                                } else if (log.startsWith('🎉') || log.startsWith('✅')) {
                                  col = const Color(0xFF34D399);
                                } else if (log.startsWith('⚠️')) {
                                  col = const Color(0xFFFBBF24);
                                } else if (log.startsWith('❌')) {
                                  col = const Color(0xFFF87171);
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      color: col,
                                      height: 1.35,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text('Chọn', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceLight,
                foregroundColor: Colors.white,
                elevation: 0,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = items.contains(value) ? value : (items.isNotEmpty ? items.first : value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: validValue,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
              items: items.map((it) {
                return DropdownMenuItem<String>(
                  value: it,
                  child: Text(it, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyValueDropdown({
    required String label,
    required String value,
    required List<Map<String, String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = items.any((it) => it['value'] == value)
        ? value
        : (items.isNotEmpty ? items.first['value']! : value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: validValue,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSecondary),
              items: items.map((it) {
                return DropdownMenuItem<String>(
                  value: it['value'],
                  child: Text(it['name'] ?? it['value']!, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
