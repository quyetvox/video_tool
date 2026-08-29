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

    test('parse config with heavy inline comments and quotes', () {
      const yaml = '''
inpaint:
  engine: apple_vision_inpaint
  show_box: false
  box:
    bg_color: "black"          # Màu nền: black | white | #1e1e1e | #0f172a
    border_color: "&H40FFFFFF" # Màu viền: Trắng mờ
subtitle:
  order: "primary_top"         # primary_top (Chính trên, phụ dưới)
  font_color: "&H00FFFFFF"     # &H00FFFFFF (Trắng)
  font_size: 24              # Kích thước chữ dòng chính (px)
tts:
  voice: "vi"                    # Giọng mặc định Ban Mai
watermark:
  enabled: false
  text: "Sub-Video AI"         # Chữ hiển thị
''';

      final config = YamlConfigParser.parse(yaml);
      expect(config.inpaintEngine, 'apple_vision_inpaint');
      expect(config.inpaintShowBox, false);
      expect(config.boxBgColor, 'black');
      expect(config.boxBorderColor, '&H40FFFFFF');
      expect(config.subtitleOrder, 'primary_top');
      expect(config.fontColor, '&H00FFFFFF');
      expect(config.fontSize, '24');
      expect(config.ttsVoice, 'vi');
      expect(config.watermarkEnabled, false);
      expect(config.watermarkText, 'Sub-Video AI');
    });

    test('parse empty string returns default config', () {
      final config = YamlConfigParser.parse('');
      expect(config.device, 'auto');
      expect(config.targetLang, 'vi');
      expect(config.inpaintRegion, isNull);
    });
  });
}
