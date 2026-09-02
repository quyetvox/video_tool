import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/app_config.dart';
import 'package:sub_video_desktop/utils/yaml_config_parser.dart';
import 'package:sub_video_desktop/utils/yaml_config_serializer.dart';

void main() {
  test('batch_cooldown_sec roundtrip and defaults', () {
    // 1. Defaults
    final defCfg = AppConfig.defaults();
    expect(defCfg.batchCooldownSec, 'auto');

    // 2. Parse from YAML
    const yamlStr = '''
app:
  device: auto
  video_bitrate: "2.5M"
  output_suffix: "_vi"
  batch_cooldown_sec: "8"
''';
    final parsed = YamlConfigParser.parse(yamlStr);
    expect(parsed.batchCooldownSec, '8');

    // 3. Serialize to YAML
    final serialized = YamlConfigSerializer.serialize(parsed);
    expect(serialized.contains('batch_cooldown_sec: "8"'), isTrue);
  });
}
