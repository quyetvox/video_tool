import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/file_service.dart';
import 'package:sub_video_desktop/utils/yaml_config_parser.dart';
import 'package:sub_video_desktop/utils/yaml_config_serializer.dart';

void main() {
  test('E2E project creation, modification and clean serialization', () {
    final tempDir = Directory('test_resources_e2e');
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    tempDir.createSync();

    try {
      // 1. Create project
      final ok = FileService.createProject('test_resources_e2e', 'demo_test_proj', rootDir: '..');
      expect(ok, isTrue);

      // 2. Read config
      final projYaml = FileService.readProjectConfig('test_resources_e2e', 'demo_test_proj');
      var config = YamlConfigParser.parse(projYaml);
      expect(config.boxBgColor, 'black');
      expect(config.subtitleOrder, 'primary_top');

      // 3. User updates values on GUI (with possible dirty inputs)
      config = config.copyWith(
        boxBgColor: '"white" # user picked white',
        subtitleOrder: 'secondary_top',
        fontSize: '22',
        targetLang: 'vi',
        secondaryLang: 'en',
        watermarkEnabled: false,
        inpaintEngine: 'apple_vision_inpaint',
        inpaintShowBox: false,
      );

      // 4. Save to disk
      final newYaml = YamlConfigSerializer.serialize(config);
      FileService.writeProjectConfig('test_resources_e2e', 'demo_test_proj', newYaml);

      // 5. Read back & verify
      final savedYaml = FileService.readProjectConfig('test_resources_e2e', 'demo_test_proj');
      final reloaded = YamlConfigParser.parse(savedYaml);
      expect(reloaded.boxBgColor, 'white');
      expect(reloaded.subtitleOrder, 'secondary_top');
      expect(reloaded.fontSize, '22');
      expect(reloaded.watermarkEnabled, isFalse);
      expect(reloaded.inpaintEngine, 'apple_vision_inpaint');
      expect(reloaded.inpaintShowBox, isFalse);
      expect(savedYaml, isNot(matches(RegExp(r'""[a-zA-Z0-9_&]'))));
    } finally {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  });
}
