import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ai_connection_tester.dart';
import '../core/app_colors.dart';
import '../core/providers.dart';
import '../models/app_config.dart';
import '../widgets/resizable_collapsible_panel.dart';
import 'config_editor/components/config_category_sidebar.dart';
import 'config_editor/components/sections/config_app_device_section.dart';
import 'config_editor/components/sections/config_audio_volumes_section.dart';
import 'config_editor/components/sections/config_hardware_section.dart';
import 'config_editor/components/sections/config_inpaint_section.dart';
import 'config_editor/components/sections/config_storage_section.dart';
import 'config_editor/components/sections/config_subtitles_section.dart';
import 'config_editor/components/sections/config_translator_section.dart';
import 'config_editor/components/sections/config_voice_tts_section.dart';
import 'config_editor/components/sections/config_watermark_section.dart';

class ConfigEditorScreen extends ConsumerStatefulWidget {
  const ConfigEditorScreen({super.key});

  @override
  ConsumerState<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends ConsumerState<ConfigEditorScreen> {
  bool _isTestingAi = false;
  String _selectedCategory = 'all';

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
                const Text('Kết quả dịch mẫu ("Hello World"):',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
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
              child: const Text('Đóng', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final activeProject = ref.watch(activeProjectProvider);
    final availableFonts = ref.watch(availableFontsProvider).map((f) => f.name).toList();
    final notifier = ref.read(configProvider.notifier);
    final c = AppColors.of(context);

    return Container(
      color: c.background,
      child: Column(
        children: [
          // ── TOP HEADER ACTION BAR ────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, color: c.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Cấu hình dự án: ${activeProject ?? "Mặc định (Root)"}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: c.textPrimary),
                ),
              ],
            ),
          ),

          // ── MAIN CONTENT (Resizable Side Category + Sections Editor) ──
          Expanded(
            child: ResizableCollapsiblePanel(
              side: PanelSide.left,
              initialWidth: 230,
              minWidth: 170,
              maxWidth: 320,
              collapseTooltip: 'Thu gọn danh mục cấu hình',
              expandTooltip: 'Mở danh mục cấu hình',
              panel: ConfigCategorySidebar(
                selectedCategory: _selectedCategory,
                onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
              ),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_selectedCategory == 'all' || _selectedCategory == 'app') ...[
                    ConfigAppDeviceSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'ai') ...[
                    ConfigTranslatorSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                      isTestingAi: _isTestingAi,
                      onTestAiConnection: () => _testAiConnection(config),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'inpaint') ...[
                    ConfigInpaintSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'subtitles') ...[
                    ConfigSubtitlesSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                      availableFonts: availableFonts,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'voice') ...[
                    ConfigVoiceTtsSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                    ),
                    const SizedBox(height: 16),
                    ConfigAudioVolumesSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'watermark') ...[
                    ConfigWatermarkSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                      availableFonts: availableFonts,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'hardware') ...[
                    ConfigHardwareSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_selectedCategory == 'all' || _selectedCategory == 'storage') ...[
                    ConfigStorageSection(
                      cfg: config,
                      onUpdate: notifier.setField,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
