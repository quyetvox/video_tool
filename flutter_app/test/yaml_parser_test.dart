import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/utils/yaml_config_parser.dart';

void main() {
  group('YamlConfigParser Tests', () {
    test('parse standard config.yaml string', () {
      const yaml = '''
app:
  device: auto
  target_lang: vi
  secondary_lang: "en"
  ocr_only: false
  video_bitrate: "4.0M"
  output_suffix: "_vi"

inpaint:
  show_box: true
  engine: box_color
  method: "vertical_gradient"
  padding_y: 0.02
  color: "black"
  blur_radius: 15
  # region: [0.12, 0.05, 0.22, 0.95]
  box:
    bg_color: "black"
    bg_opacity: 0.75
    border_color: "&H40FFFFFF"
    border_width: 2
    border_radius: 8

subtitle:
  show: true
  show_primary: true
  region: [0.75, 0.05, 0.95, 0.95]
  font_name: "Arial"
  font_size: 28
  font_color: "&H00FFFFFF"
  outline_color: "&H00000000"
''';

      final config = YamlConfigParser.parse(yaml);
      expect(config.device, 'auto');
      expect(config.targetLang, 'vi');
      expect(config.secondaryLang, 'en');
      expect(config.ocrOnly, false);
      expect(config.inpaintRegion, isNull); // commented region should be null
      expect(config.subtitleRegion, equals([0.75, 0.05, 0.95, 0.95]));
      expect(config.boxBorderRadius, 8);
      expect(config.fontSize, '28');
    });

    test('parse uncommented inpaint region', () {
      const yaml = '''
inpaint:
  region: [0.12, 0.05, 0.22, 0.95]
''';
      final config = YamlConfigParser.parse(yaml);
      expect(config.inpaintRegion, equals([0.12, 0.05, 0.22, 0.95]));
    });

    test('parse empty string returns default config', () {
      final config = YamlConfigParser.parse('');
      expect(config.device, 'auto');
      expect(config.targetLang, 'vi');
      expect(config.inpaintRegion, isNull);
    });
  });
}
