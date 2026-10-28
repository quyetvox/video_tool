import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/config_notifier.dart';
import 'package:sub_video_desktop/core/providers.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/screens/config_editor/components/sections/config_app_device_section.dart';
import 'package:sub_video_desktop/screens/config_editor/components/sections/config_voice_tts_section.dart';
import 'package:sub_video_desktop/utils/yaml_config_parser.dart';
import 'package:sub_video_desktop/utils/yaml_config_serializer.dart';
import 'package:sub_video_desktop/widgets/subtitle_inspector_widget.dart';

class _FakeConfigNotifier extends ConfigNotifier {
  _FakeConfigNotifier(AppConfig initial) : super(rootDir: '') {
    state = initial;
  }
}

void main() {
  group('Multilingual Voice TTS & Secondary Language Configuration Tests', () {
    testWidgets('ConfigVoiceTtsSection shows Vietnamese voices when targetLang is vi', (tester) async {
      AppConfig cfg = AppConfig.defaults().copyWith(targetLang: 'vi');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfigVoiceTtsSection(
              cfg: cfg,
              onUpdate: (fn) => cfg = fn(cfg),
            ),
          ),
        ),
      );

      // Verify Vietnamese subtitle description
      expect(find.text('Engine sinh giọng đọc EdgeTTS / gTTS và phân biệt giới tính Nam/Nữ'), findsOneWidget);
      // Verify default Vietnamese voice is present
      expect(find.text('🇻🇳 Hoài My (Nữ truyền cảm - EdgeTTS)'), findsOneWidget);
    });

    testWidgets('ConfigVoiceTtsSection shows English voices when targetLang is en', (tester) async {
      AppConfig cfg = AppConfig.defaults().copyWith(
        targetLang: 'en',
        ttsVoice: 'en-US-JennyNeural',
        ttsVoiceMale: 'en-US-GuyNeural',
        ttsVoiceFemale: 'en-US-JennyNeural',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConfigVoiceTtsSection(
              cfg: cfg,
              onUpdate: (fn) => cfg = fn(cfg),
            ),
          ),
        ),
      );

      // Verify English active subtitle
      expect(find.text('Đang kích hoạt gói giọng đọc Tiếng Anh (EdgeTTS US/UK/AU) cho mục tiêu dịch "en"'), findsOneWidget);
      // Verify English voice label
      expect(find.text('🇺🇸 Jenny (Nữ Mỹ tự nhiên)'), findsOneWidget);
      expect(find.text('Giọng đọc Tiếng Anh mặc định:'), findsOneWidget);
    });

    testWidgets('ConfigAppDeviceSection auto-switches TTS voices when targetLang toggles en/vi', (tester) async {
      AppConfig cfg = AppConfig.defaults().copyWith(
        targetLang: 'vi',
        ttsVoice: 'vi-VN-HoaiMyNeural',
        ttsVoiceMale: 'vi-VN-NamMinhNeural',
        ttsVoiceFemale: 'vi-VN-HoaiMyNeural',
      );


      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ConfigAppDeviceSection(
                  cfg: cfg,
                  onUpdate: (fn) {
                    setState(() {
                      cfg = fn(cfg);
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Find the target_lang dropdown
      final targetLangDropdownFinder = find.byWidgetPredicate(
        (widget) => widget is DropdownButton<String> && widget.value == 'vi',
      );
      expect(targetLangDropdownFinder, findsOneWidget);

      // Select 'en'
      await tester.tap(targetLangDropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('🇺🇸 Tiếng Anh (en)').last);
      await tester.pumpAndSettle();

      // Verify that cfg was auto-updated to English target and English voice
      expect(cfg.targetLang, 'en');
      expect(cfg.ttsVoice, 'en-US-JennyNeural');
      expect(cfg.ttsVoiceMale, 'en-US-GuyNeural');
      expect(cfg.ttsVoiceFemale, 'en-US-JennyNeural');
    });

    testWidgets('ConfigAppDeviceSection supports secondary_lang dropdown and custom mode switch', (tester) async {
      AppConfig cfg = AppConfig.defaults().copyWith(
        targetLang: 'en',
        secondaryLang: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ConfigAppDeviceSection(
                  cfg: cfg,
                  onUpdate: (fn) {
                    setState(() {
                      cfg = fn(cfg);
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      // Verify secondary lang dropdown is present with 'Tắt (Chỉ làm đơn ngữ)'
      expect(find.text('Tắt (Chỉ làm đơn ngữ)'), findsOneWidget);

      // Tap dropdown to select Vietnamese secondary_lang
      final secDropdownFinder = find.byWidgetPredicate(
        (widget) => widget is DropdownButton<String> && widget.value == '',
      );
      expect(secDropdownFinder, findsOneWidget);

      await tester.tap(secDropdownFinder);
      await tester.pumpAndSettle();

      // Choose Vietnamese secondary
      await tester.tap(find.text('🇻🇳 Tiếng Việt (vi)').last);
      await tester.pumpAndSettle();

      expect(cfg.secondaryLang, 'vi');
      expect(find.text('🇻🇳 Tiếng Việt (vi)'), findsOneWidget);
    });

    test('AppConfig preserves Vietnamese secondary_lang in YAML parsing and serializing', () {
      final config = AppConfig.defaults().copyWith(
        targetLang: 'en',
        secondaryLang: 'vi',
        subtitleSecondaryShow: true,
      );

      final yamlStr = YamlConfigSerializer.serialize(config);
      expect(yamlStr.contains('secondary_lang: "vi"'), isTrue);

      final parsed = YamlConfigParser.parse(yamlStr);
      expect(parsed.secondaryLang, 'vi');
      expect(parsed.subtitleSecondaryShow, isTrue);
    });

    testWidgets('SubtitleInspectorWidget Voice & Audio tab displays English voices when targetLang is en', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final config = AppConfig.defaults().copyWith(
        targetLang: 'en',
        ttsVoice: 'en-US-JennyNeural',
        ttsVoiceMale: 'en-US-GuyNeural',
        ttsVoiceFemale: 'en-US-JennyNeural',
      );

      final container = ProviderContainer(
        overrides: [
          configProvider.overrideWith((ref) => _FakeConfigNotifier(config)),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SubtitleInspectorWidget(
                subtitles: const [],
                currentTime: 0.0,
                onSubtitleChange: (_) {},
                onTranslateAll: () {},
                onAutoSync: () {},
                onSaveSubtitles: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Voice & Audio tab
      final voiceTabFinder = find.text('🎙️ Voice & Audio');
      expect(voiceTabFinder, findsOneWidget);
      await tester.tap(voiceTabFinder);
      await tester.pumpAndSettle();

      // Verify English edgeTTS section header and English voice
      expect(find.text('1. THUYẾT MINH AI (EDGETTS ENGLISH)'), findsOneWidget);
      expect(find.text('🇺🇸 en-US-JennyNeural (Nữ Mỹ - Tự nhiên)'), findsWidgets);
    });
  });
}

