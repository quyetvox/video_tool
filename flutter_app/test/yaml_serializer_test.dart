import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/utils/yaml_config_parser.dart';
import 'package:sub_video_desktop/utils/yaml_config_serializer.dart';

void main() {
  group('YamlConfigSerializer Tests', () {
    test('round-trip serialize and parse preserves config values', () {
      final initial = AppConfig.defaults().copyWith(
        targetLang: 'ja',
        secondaryLang: 'vi',
        ocrOnly: true,
        inpaintRegion: [0.15, 0.05, 0.25, 0.95],
        boxBgColor: '#1e1e1e',
        boxBgOpacity: 0.85,
        fontName: 'Montserrat',
        fontSize: '32',
        watermarkText: 'Custom Watermark',
        ttsSpeed: 1.25,
      );

      final yamlString = YamlConfigSerializer.serialize(initial);
      expect(yamlString, contains('target_lang: ja'));
      expect(yamlString, contains('ocr_only: true'));
      expect(yamlString, contains('region: [0.15, 0.05, 0.25, 0.95]'));
      expect(yamlString, contains('font_size: 32'));
      expect(yamlString, contains('text: "Custom Watermark"'));

      final parsed = YamlConfigParser.parse(yamlString);
      expect(parsed.targetLang, 'ja');
      expect(parsed.secondaryLang, 'vi');
      expect(parsed.ocrOnly, true);
      expect(parsed.inpaintRegion, equals([0.15, 0.05, 0.25, 0.95]));
      expect(parsed.boxBgColor, '#1e1e1e');
      expect(parsed.boxBgOpacity, 0.85);
      expect(parsed.fontName, 'Montserrat');
      expect(parsed.fontSize, '32');
      expect(parsed.watermarkText, 'Custom Watermark');
      expect(parsed.ttsSpeed, 1.25);
    });
  });
}
