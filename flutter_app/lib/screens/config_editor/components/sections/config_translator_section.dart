import 'package:flutter/material.dart';
import '../../../../models/app_config.dart';
import '../../../../widgets/app_kit.dart';
import '../../../../widgets/settings_section_card.dart';
import '../config_input_fields.dart';

class ConfigTranslatorSection extends StatelessWidget {
  final AppConfig cfg;
  final void Function(AppConfig Function(AppConfig)) onUpdate;
  final bool isTestingAi;
  final VoidCallback onTestAiConnection;

  const ConfigTranslatorSection({
    super.key,
    required this.cfg,
    required this.onUpdate,
    required this.isTestingAi,
    required this.onTestAiConnection,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: '2. Dịch Thuật AI (AI Translation Provider)',
      icon: Icons.translate_rounded,
      subtitle: 'Cấu hình nhà cung cấp LLM, model và API endpoint',
      trailing: AppButton.secondary(
        label: isTestingAi ? 'Đang test...' : 'Kiểm Tra Kết Nối AI',
        icon: Icons.bolt,
        height: 30,
        fontSize: 11,
        isLoading: isTestingAi,
        onPressed: isTestingAi ? null : onTestAiConnection,
      ),
      children: [
        ConfigRow2(
          w1: ConfigDropdown(
            label: 'Nhà cung cấp AI (Provider):',
            value: cfg.translatorType,
            options: const [
              'ollama',
              'openai',
              'gemini',
              'deepseek',
              'groq',
              'openrouter',
              'custom',
            ],
            onChanged: (val) {
              if (val == null) return;
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
              onUpdate((c) => c.copyWith(
                    translatorType: val,
                    translatorBaseUrl: defaultBaseUrl,
                    translatorModel: defaultModel,
                  ));
            },
          ),
          w2: ConfigTextField(
            label: 'Tên Model (model):',
            value: cfg.translatorModel,
            placeholder: cfg.translatorType == 'ollama'
                ? 'qwen2.5-coder:latest, gemma4:31b-cloud...'
                : 'gpt-4o-mini, deepseek-chat, gemini-3.1-flash-lite...',
            onChanged: (val) => onUpdate((c) => c.copyWith(translatorModel: val)),
          ),
        ),
        const SizedBox(height: 12),
        ConfigRow2(
          w1: ConfigTextField(
            label: 'Base URL kết nối (base_url):',
            value: cfg.translatorBaseUrl,
            placeholder: 'https://api.openai.com/v1 hoặc http://localhost:11434',
            onChanged: (val) => onUpdate((c) => c.copyWith(translatorBaseUrl: val)),
          ),
          w2: ConfigTextField(
            label: 'Kích thước mẻ dịch (batch_size):',
            value: cfg.translatorBatchSize.toString(),
            placeholder: 'Số câu dịch mỗi lượt (mặc định: 20)',
            onChanged: (val) {
              final n = int.tryParse(val) ?? 20;
              onUpdate((c) => c.copyWith(translatorBatchSize: n));
            },
          ),
        ),
        const SizedBox(height: 12),
        ConfigPasswordField(
          label: 'API Key (api_key):',
          value: cfg.translatorApiKey,
          onChanged: (val) => onUpdate((c) => c.copyWith(translatorApiKey: val)),
        ),
      ],
    );
  }
}
