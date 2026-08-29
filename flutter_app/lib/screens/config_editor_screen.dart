import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ai_connection_tester.dart';
import '../core/providers.dart';
import '../models/app_config.dart';
import '../utils/yaml_config_serializer.dart';
import '../utils/color_parser_utils.dart';
import '../widgets/compact_switch.dart';
import '../widgets/region_picker_dialog.dart';
import '../widgets/smart_color_picker_row.dart';

class ConfigEditorScreen extends ConsumerStatefulWidget {
  const ConfigEditorScreen({super.key});

  @override
  ConsumerState<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends ConsumerState<ConfigEditorScreen> {
  bool _isRawMode = false;
  bool _obscureApiKey = true;
  bool _isTestingAi = false;
  final TextEditingController _rawYamlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(configProvider);
      _rawYamlController.text = YamlConfigSerializer.serialize(config);
    });
  }

  @override
  void dispose() {
    _rawYamlController.dispose();
    super.dispose();
  }

  void _syncToRawYaml() {
    final config = ref.read(configProvider);
    _rawYamlController.text = YamlConfigSerializer.serialize(config);
  }

  Future<void> _testAiConnection(AppConfig cfg) async {
    setState(() => _isTestingAi = true);
    final res = await AiConnectionTester.testConnection(
      providerType: cfg.translatorType,
      baseUrl: cfg.translatorBaseUrl,
      model: cfg.translatorModel,
      apiKey: cfg.translatorApiKey,
    );
    setState(() => _isTestingAi = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(
                res.success ? Icons.check_circle : Icons.error_outline,
                color: res.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                res.success ? 'Kết Nối AI Thành Công' : 'Kết Nối AI Thất Bại',
                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                res.message,
                style: TextStyle(
                  fontSize: 13,
                  color: res.success ? const Color(0xFF34D399) : const Color(0xFFF87171),
                ),
              ),
              if (res.latencyMs != null) ...[
                const SizedBox(height: 8),
                Text('Độ trễ phản hồi: ${res.latencyMs} ms', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
              if (res.translatedSample != null && res.translatedSample!.isNotEmpty) ...[
                const Divider(color: Color(0xFF1E293B), height: 20),
                const Text('Kết quả dịch mẫu ("Hello World"):', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    res.translatedSample!,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng', style: TextStyle(color: Color(0xFF06B6D4))),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = ref.watch(configProvider);
    final activeProject = ref.watch(activeProjectProvider);

    return Column(
      children: [
        // ── TOP HEADER ACTION BAR ────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune, color: Colors.cyanAccent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Cấu hình dự án: ${activeProject ?? "Mặc định (Root)"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),

              // Switch Mode: GUI / Raw YAML
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('GUI Mode'), icon: Icon(Icons.dashboard_customize_outlined, size: 14)),
                  ButtonSegment(value: true, label: Text('Raw YAML'), icon: Icon(Icons.code, size: 14)),
                ],
                selected: {_isRawMode},
                onSelectionChanged: (set) {
                  setState(() {
                    _isRawMode = set.first;
                    if (_isRawMode) _syncToRawYaml();
                  });
                },
              ),
              const SizedBox(width: 12),

              // Save Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Lưu Cấu Hình (config.yaml)'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  if (_isRawMode) {
                    await ref.read(configProvider.notifier).saveRawYaml(_rawYamlController.text);
                  } else {
                    await ref.read(configProvider.notifier).save();
                  }
                  messenger.showSnackBar(
                    const SnackBar(content: Text('💾 Đã lưu cấu hình config.yaml thành công!'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ],
          ),
        ),

        // ── MAIN CONTENT (GUI or Raw Editor) ─────────────────────────
        Expanded(
          child: _isRawMode
              ? _buildRawYamlEditor(isDark)
              : _buildGuiEditor(context, config, isDark),
        ),
      ],
    );
  }

  Widget _buildRawYamlEditor(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: TextField(
        controller: _rawYamlController,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
        decoration: InputDecoration(
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildGuiEditor(BuildContext context, AppConfig cfg, bool isDark) {
    final notifier = ref.read(configProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── SECTION 1: App & Device ──────────────────────────────────
        _buildSectionCard(
          title: '1. Ứng Dụng & Thiết Bị (App & Device)',
          icon: Icons.computer,
          isDark: isDark,
          children: [
            _buildRow2(
              _buildDropdown('Thiết bị (device):', cfg.device, ['auto', 'mps', 'cuda', 'cpu'], (val) {
                notifier.setField((c) => c.copyWith(device: val));
              }),
              _buildDropdown('Ngôn ngữ dịch chính:', cfg.targetLang, ['vi', 'en', 'zh', 'ja', 'ko', 'fr', 'es'], (val) {
                notifier.setField((c) => c.copyWith(targetLang: val));
              }),
            ),
            const SizedBox(height: 12),
            _buildRow2(
              _buildTextField('Ngôn ngữ phụ song ngữ (secondary_lang):', cfg.secondaryLang, (val) {
                notifier.setField((c) => c.copyWith(secondaryLang: val));
              }, hint: 'en, zh, ja... để trống nếu chỉ đơn ngữ'),
              _buildDropdown('Chất lượng Bitrate Video:', cfg.videoBitrate, ['4.0M', '2.5M', '1.5M', '6.0M'], (val) {
                notifier.setField((c) => c.copyWith(videoBitrate: val));
              }),
            ),
            const SizedBox(height: 12),
            _buildToggle(
              'Chế độ Dịch Sub Cứng Hình Ảnh (ocr_only)',
              cfg.ocrOnly,
              (val) => notifier.setField((c) => c.copyWith(ocrOnly: val)),
              subtitle: 'Bỏ qua Whisper & Demucs (~0s audio), giữ 100% âm thanh gốc, chỉ dịch chữ phụ đề',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 2: AI Translator ─────────────────────────────────
        _buildSectionCard(
          title: '2. Dịch Thuật AI (AI Translation Provider)',
          icon: Icons.translate_rounded,
          isDark: isDark,
          children: [
            _buildRow2(
              _buildDropdown('Nhà cung cấp AI (Provider):', cfg.translatorType, [
                'ollama',
                'openai',
                'gemini',
                'deepseek',
                'groq',
                'openrouter',
                'custom',
              ], (val) {
                var defaultBaseUrl = cfg.translatorBaseUrl;
                var defaultModel = cfg.translatorModel;
                if (val == 'ollama') {
                  defaultBaseUrl = 'http://localhost:11434';
                  defaultModel = 'gemma4:31b-cloud';
                } else if (val == 'deepseek') {
                  defaultBaseUrl = 'https://api.deepseek.com/v1';
                  defaultModel = 'deepseek-chat';
                } else if (val == 'groq') {
                  defaultBaseUrl = 'https://api.groq.com/openai/v1';
                  defaultModel = 'llama-3.3-70b-versatile';
                } else if (val == 'openrouter') {
                  defaultBaseUrl = 'https://openrouter.ai/api/v1';
                  defaultModel = 'qwen/qwen-2.5-72b-instruct';
                } else if (val == 'gemini') {
                  defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
                  defaultModel = 'gemini-3.1-flash-lite';
                } else if (val == 'openai') {
                  defaultBaseUrl = 'https://api.openai.com/v1';
                  defaultModel = 'gpt-4o-mini';
                }
                notifier.setField((c) => c.copyWith(
                  translatorType: val,
                  translatorBaseUrl: defaultBaseUrl,
                  translatorModel: defaultModel,
                ));
              }),
              _buildTextField('Tên Model (model):', cfg.translatorModel, (val) {
                notifier.setField((c) => c.copyWith(translatorModel: val));
              }, hint: cfg.translatorType == 'ollama' ? 'qwen2.5-coder:latest, gemma4:31b-cloud...' : 'gpt-4o-mini, deepseek-chat, gemini-3.1-flash-lite...'),
            ),
            const SizedBox(height: 12),
            _buildRow2(
              _buildTextField('Base URL kết nối (base_url):', cfg.translatorBaseUrl, (val) {
                notifier.setField((c) => c.copyWith(translatorBaseUrl: val));
              }, hint: 'https://api.openai.com/v1 hoặc http://localhost:11434'),
              _buildTextField('Kích thước mẻ dịch (batch_size):', cfg.translatorBatchSize.toString(), (val) {
                final n = int.tryParse(val) ?? 20;
                notifier.setField((c) => c.copyWith(translatorBatchSize: n));
              }, hint: 'Số câu dịch mỗi lượt (mặc định: 20)'),
            ),
            const SizedBox(height: 12),
            _buildPasswordField('API Key (api_key):', cfg.translatorApiKey, (val) {
              notifier.setField((c) => c.copyWith(translatorApiKey: val));
            }, hint: 'sk-... hoặc token chứng thực (Ollama để trống nếu chạy local)'),
            const SizedBox(height: 14),
            Row(
              children: [
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: _isTestingAi
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bolt, size: 16),
                  label: Text(_isTestingAi ? 'Đang gọi AI test...' : 'Kiểm Tra Kết Nối AI (Test Connection)'),
                  onPressed: _isTestingAi ? null : () => _testAiConnection(cfg),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 3: Inpaint & SubBox ──────────────────────────────
        _buildSectionCard(
          title: '3. Xóa Sub Cũ & Hộp Nền Che (Inpaint & SubBox)',
          icon: Icons.brush_outlined,
          isDark: isDark,
          children: [
            _buildRow2(
              _buildDropdown('Công cụ xóa sub (engine):', cfg.inpaintEngine, ['box_color', 'ffmpeg_blur', 'apple_vision_inpaint', 'opencv'], (val) {
                notifier.setField((c) => c.copyWith(inpaintEngine: val));
              }),
              _buildDropdown('Thuật toán xóa (method):', cfg.inpaintMethod, ['vertical_gradient', 'navier_stokes', 'telea'], (val) {
                notifier.setField((c) => c.copyWith(inpaintMethod: val));
              }),
            ),
            const SizedBox(height: 12),
            SmartColorPickerRow(
              label: 'Màu nền hộp che (bg_color):',
              currentColor: cfg.boxBgColor,
              presets: const [
                ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
                ColorPreset(label: '🌑 Đen Slate (#0f172a)', code: '#0f172a', previewColor: Color(0xFF0F172A)),
                ColorPreset(label: '🔘 Xám Đậm (#1e1e1e)', code: '#1e1e1e', previewColor: Color(0xFF1E1E1E)),
                ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
              ],
              onChanged: (val) => notifier.setField((c) => c.copyWith(boxBgColor: val)),
            ),
            const SizedBox(height: 8),
            _buildSlider('Độ đậm nền (bg_opacity):', cfg.boxBgOpacity, 0.1, 1.0, (val) {
              notifier.setField((c) => c.copyWith(boxBgOpacity: val));
            }),
            const SizedBox(height: 12),
            SmartColorPickerRow(
              label: 'Màu viền hộp (border_color):',
              currentColor: cfg.boxBorderColor,
              presets: const [
                ColorPreset(label: '⚪ Trắng Mờ (&H40FFFFFF)', code: '&H40FFFFFF', previewColor: Color(0xC0FFFFFF)),
                ColorPreset(label: '🟡 Vàng Sáng (&H0000FFFF)', code: '&H0000FFFF', previewColor: Color(0xFFFFFF00)),
                ColorPreset(label: '🔵 Xanh Cyan (&H00FFFF00)', code: '&H00FFFF00', previewColor: Color(0xFF00FFFF)),
                ColorPreset(label: '🚫 Không Viền (none)', code: 'none', previewColor: Colors.transparent),
              ],
              onChanged: (val) => notifier.setField((c) => c.copyWith(boxBorderColor: val)),
            ),
            const SizedBox(height: 8),
            _buildSlider('Bo góc viền (border_radius):', cfg.boxBorderRadius.toDouble(), 0, 20, (val) {
              notifier.setField((c) => c.copyWith(boxBorderRadius: val.toInt()));
            }),
            const SizedBox(height: 8),
            _buildRow2(
              _buildTextField('Mở sớm hộp che (box_lead_in):', cfg.boxLeadIn.toString(), (val) {
                notifier.setField((c) => c.copyWith(boxLeadIn: double.tryParse(val) ?? 0.25));
              }),
              _buildTextField('Đóng trễ hộp che (box_lead_out):', cfg.boxLeadOut.toString(), (val) {
                notifier.setField((c) => c.copyWith(boxLeadOut: double.tryParse(val) ?? 0.15));
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    cfg.inpaintRegion != null
                        ? 'Vùng sub override thủ công: [${cfg.inpaintRegion!.join(", ")}]'
                        : 'Vùng sub cũ: Tự động phát hiện (Auto Detect)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.crop, size: 14),
                  label: const Text('Chọn vùng Sub (Region Picker)'),
                  onPressed: () async {
                    final res = await RegionPickerDialog.show(
                      context,
                      title: 'Chọn Vùng Sub Cũ (Inpaint Region)',
                      initialRegion: cfg.inpaintRegion,
                    );
                    if (res != null) {
                      notifier.setField((c) => c.copyWith(inpaintRegion: res));
                    }
                  },
                ),
                if (cfg.inpaintRegion != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => notifier.setField((c) => c.copyWith(setInpaintRegionNull: true)),
                    child: const Text('Đặt lại Auto'),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 3: Subtitle Primary ──────────────────────────────
        _buildSectionCard(
          title: '3. Phụ Đề Mới (Subtitle Primary)',
          icon: Icons.subtitles,
          isDark: isDark,
          children: [
            _buildToggle(
              'Hiển thị Phụ Đề Mới trên Video (show)',
              cfg.showSubtitle,
              (val) => notifier.setField((c) => c.copyWith(showSubtitle: val)),
            ),
            const SizedBox(height: 8),
            _buildRow2(
              _buildDropdown('Font chữ (font_name):', cfg.fontName.isNotEmpty ? cfg.fontName : 'Arial', ref.watch(availableFontsProvider).map((f) => f.name).toList(), (val) {
                notifier.setField((c) => c.copyWith(fontName: val));
              }),
              _buildTextField('Cỡ chữ font_size (để trống = auto fit):', cfg.fontSize, (val) {
                notifier.setField((c) => c.copyWith(fontSize: val));
              }),
            ),
            const SizedBox(height: 12),
            SmartColorPickerRow(
              label: 'Màu chữ chính (font_color):',
              currentColor: cfg.fontColor,
              presets: const [
                ColorPreset(label: '⚪ Trắng Chuẩn (&H00FFFFFF)', code: '&H00FFFFFF', previewColor: Colors.white),
                ColorPreset(label: '🟡 Vàng Nổi Bật (&H0000FFFF)', code: '&H0000FFFF', previewColor: Color(0xFFFFFF00)),
                ColorPreset(label: '🔵 Xanh Cyan (&H00FFFF00)', code: '&H00FFFF00', previewColor: Color(0xFF00FFFF)),
                ColorPreset(label: '🔴 Đỏ Nổi Bật (&H000000FF)', code: '&H000000FF', previewColor: Color(0xFFFF0000)),
                ColorPreset(label: '⚫ Đen (&H00000000)', code: '&H00000000', previewColor: Colors.black),
              ],
              onChanged: (val) => notifier.setField((c) => c.copyWith(fontColor: val)),
            ),
            const SizedBox(height: 8),
            _buildTextField('Màu viền chữ (outline_color):', cfg.outlineColor, (val) {
              notifier.setField((c) => c.copyWith(outlineColor: val));
            }),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 4: TTS & Voice ───────────────────────────────────
        _buildSectionCard(
          title: '4. Thuyết Minh Giọng Đọc AI (TTS Voice)',
          icon: Icons.record_voice_over,
          isDark: isDark,
          children: [
            _buildRow2(
              _buildDropdown('Giọng đọc EdgeTTS:', cfg.ttsVoice, ['vi', 'vi-VN-HoaiMyNeural', 'vi-VN-NamMinhNeural', '0'], (val) {
                notifier.setField((c) => c.copyWith(ttsVoice: val));
              }),
              _buildSlider('Tốc độ đọc (speed_factor):', cfg.ttsSpeed, 0.8, 2.0, (val) {
                notifier.setField((c) => c.copyWith(ttsSpeed: double.parse(val.toStringAsFixed(2))));
              }),
            ),
            const SizedBox(height: 12),
            _buildToggle(
              'Nhận diện giới tính Nam/Nữ để đổi giọng đọc (enable_gender)',
              cfg.enableGenderTts,
              (val) => notifier.setField((c) => c.copyWith(enableGenderTts: val)),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 5: Audio Volumes ─────────────────────────────────
        _buildSectionCard(
          title: '5. Âm Lượng & Bộ Lọc Âm Thanh (Audio Volumes)',
          icon: Icons.volume_up,
          isDark: isDark,
          children: [
            _buildRow2(
              _buildSlider('Giọng đọc TTS (tts_voice):', cfg.ttsVol, 0.0, 2.0, (val) {
                notifier.setField((c) => c.copyWith(ttsVol: double.parse(val.toStringAsFixed(2))));
              }),
              _buildSlider('Giọng gốc (original_voice):', cfg.origVoiceVol, 0.0, 1.0, (val) {
                notifier.setField((c) => c.copyWith(origVoiceVol: double.parse(val.toStringAsFixed(2))));
              }),
            ),
            const SizedBox(height: 12),
            _buildRow2(
              _buildSlider('Nhạc nền (music):', cfg.musicVol, 0.0, 1.0, (val) {
                notifier.setField((c) => c.copyWith(musicVol: double.parse(val.toStringAsFixed(2))));
              }),
              _buildSlider('Âm thanh môi trường (ambient):', cfg.ambientVol, 0.0, 1.0, (val) {
                notifier.setField((c) => c.copyWith(ambientVol: double.parse(val.toStringAsFixed(2))));
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 6: Watermark & Branding ──────────────────────────
        _buildSectionCard(
          title: '6. Watermark & Thương Hiệu (Logo Branding)',
          icon: Icons.branding_watermark_outlined,
          isDark: isDark,
          children: [
            _buildToggle(
              'Bật Watermark trên video (watermark.enabled)',
              cfg.watermarkEnabled,
              (val) => notifier.setField((c) => c.copyWith(watermarkEnabled: val)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Vùng hiển thị: [${cfg.watermarkRegion.join(", ")}]',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.crop, size: 14),
                  label: const Text('Chọn Vùng 9:16 (Region)'),
                  onPressed: () async {
                    final res = await RegionPickerDialog.show(
                      context,
                      title: 'Chọn Vùng Watermark',
                      initialRegion: cfg.watermarkRegion,
                    );
                    if (res != null) {
                      notifier.setField((c) => c.copyWith(watermarkRegion: res));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _buildTextField('Đường dẫn ảnh Logo PNG (Ưu tiên 1):', cfg.watermarkImage, (val) {
                    notifier.setField((c) => c.copyWith(watermarkImage: val));
                  }, hint: 'assets/.../logo.png'),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 14),
                    label: const Text('Chọn Ảnh...'),
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
            const SizedBox(height: 12),
            _buildRow2(
              _buildTextField('Chữ Watermark nếu không có ảnh (text):', cfg.watermarkText, (val) {
                notifier.setField((c) => c.copyWith(watermarkText: val));
              }),
              _buildDropdown('Font chữ (font_name):', cfg.watermarkFontName.isNotEmpty ? cfg.watermarkFontName : 'Arial', ref.watch(availableFontsProvider).map((f) => f.name).toList(), (val) {
                notifier.setField((c) => c.copyWith(watermarkFontName: val));
              }),
            ),
            const SizedBox(height: 12),
            SmartColorPickerRow(
              label: 'Màu chữ Watermark (font_color):',
              currentColor: cfg.watermarkFontColor,
              preferAssFormat: false,
              presets: const [
                ColorPreset(label: '⚪ Trắng (white)', code: 'white', previewColor: Colors.white),
                ColorPreset(label: '🟡 Vàng (yellow)', code: 'yellow', previewColor: Color(0xFFFFFF00)),
                ColorPreset(label: '🔵 Xanh Cyan (cyan)', code: 'cyan', previewColor: Color(0xFF00FFFF)),
                ColorPreset(label: '🔴 Đỏ (red)', code: 'red', previewColor: Color(0xFFFF0000)),
                ColorPreset(label: '⚫ Đen (black)', code: 'black', previewColor: Colors.black),
              ],
              onChanged: (val) => notifier.setField((c) => c.copyWith(watermarkFontColor: val)),
            ),
            const SizedBox(height: 8),
            _buildRow2(
              _buildSlider('Độ đậm Logo (Opacity):', cfg.watermarkOpacity, 0.1, 1.0, (val) {
                notifier.setField((c) => c.copyWith(watermarkOpacity: double.parse(val.toStringAsFixed(2))));
              }),
              _buildToggle(
                'Nền mờ kính (blur_bg)',
                cfg.watermarkBlurBg,
                (val) => notifier.setField((c) => c.copyWith(watermarkBlurBg: val)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── SECTION 7: Hardware & Concurrency ────────────────────────
        _buildSectionCard(
          title: '7. Đa Luồng & Tài Nguyên Thiết Bị (Hardware & Concurrency)',
          icon: Icons.memory,
          isDark: isDark,
          children: [
            // Hardware Info Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.developer_board, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thiết bị: ${Platform.isMacOS ? "Apple Silicon (macOS)" : Platform.operatingSystem} • ${Platform.numberOfProcessors} CPU Cores',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mặc định auto sẽ tự chọn mức trung bình chẵn (${((Platform.numberOfProcessors ~/ 2).isEven ? (Platform.numberOfProcessors ~/ 2) : (Platform.numberOfProcessors ~/ 2) - 1).clamp(2, 32)} luồng) để cân bằng tốc độ, giữ máy êm mát.',
                          style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            _buildWorkerDropdown(
              label: 'Số luồng xử lý toàn cục toàn bộ tiến trình (app.num_workers):',
              value: cfg.numWorkers,
              autoCores: ((Platform.numberOfProcessors ~/ 2).isEven ? (Platform.numberOfProcessors ~/ 2) : (Platform.numberOfProcessors ~/ 2) - 1).clamp(2, 32),
              totalCores: Platform.numberOfProcessors,
              onChanged: (val) => notifier.setField((c) => c.copyWith(numWorkers: val, ocrNumWorkers: val, ttsNumWorkers: val)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.cyanAccent, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow2(Widget w1, Widget w2) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: w1),
        const SizedBox(width: 16),
        Expanded(child: w2),
      ],
    );
  }

  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged, {String? hint}) {
    return ControlledConfigTextField(
      key: ValueKey('$label:$value'),
      label: label,
      value: value,
      onChanged: onChanged,
      hint: hint,
    );
  }

  Widget _buildPasswordField(String label, String value, ValueChanged<String> onChanged, {String? hint}) {
    return ControlledConfigTextField(
      key: ValueKey('$label:$value'),
      label: label,
      value: value,
      onChanged: onChanged,
      hint: hint,
      isPassword: true,
      obscureText: _obscureApiKey,
      onToggleObscure: () => setState(() => _obscureApiKey = !_obscureApiKey),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isExpanded: true,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkerDropdown({
    required String label,
    required String value,
    required int autoCores,
    required int totalCores,
    required ValueChanged<String> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        return 'Tự động (Auto: $autoCores luồng chẵn - Cân bằng)';
      }
      if (opt == totalCores.toString()) {
        return '$opt luồng (Tối đa $totalCores cores)';
      }
      return '$opt luồng';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : 'auto',
              isExpanded: true,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: options.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(getOptionLabel(opt), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(value.toStringAsFixed(2), style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildToggle(String title, bool value, ValueChanged<bool> onChanged, {String? subtitle}) {
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
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          CompactSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class ControlledConfigTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool isPassword;
  final bool? obscureText;
  final VoidCallback? onToggleObscure;
  final TextStyle? style;

  const ControlledConfigTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.isPassword = false,
    this.obscureText,
    this.onToggleObscure,
    this.style,
  });

  @override
  State<ControlledConfigTextField> createState() => _ControlledConfigTextFieldState();
}

class _ControlledConfigTextFieldState extends State<ControlledConfigTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant ControlledConfigTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          obscureText: widget.isPassword ? (widget.obscureText ?? true) : false,
          textAlignVertical: TextAlignVertical.center,
          style: widget.style ?? const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon((widget.obscureText ?? true) ? Icons.visibility_off : Icons.visibility, size: 16),
                    onPressed: widget.onToggleObscure,
                    tooltip: (widget.obscureText ?? true) ? 'Hiện API Key' : 'Ẩn API Key',
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
