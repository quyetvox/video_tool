import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../utils/yaml_config_parser.dart';
import '../utils/yaml_config_serializer.dart';
import 'file_service.dart';

class ConfigNotifier extends StateNotifier<AppConfig> {
  final String? project;
  final String rootDir;
  bool _hasUnsavedChanges = false;

  ConfigNotifier({
    this.project,
    required this.rootDir,
  }) : super(AppConfig.defaults()) {
    loadFromDisk();
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void loadFromDisk() {
    final yamlStr = FileService.readProjectConfig(rootDir, project ?? '');
    if (yamlStr.trim().isNotEmpty) {
      state = YamlConfigParser.parse(yamlStr);
    } else {
      state = AppConfig.defaults();
    }
    _hasUnsavedChanges = false;
  }

  /// Updates whole config in-memory only
  void updateConfig(AppConfig newConfig) {
    state = newConfig;
    _hasUnsavedChanges = true;
  }

  /// Updates state in-memory only (deferred saving)
  void setField(AppConfig Function(AppConfig current) updater) {
    state = updater(state);
    _hasUnsavedChanges = true;
  }

  /// Explicitly writes current configuration to disk
  Future<void> save() async {
    final yamlStr = YamlConfigSerializer.serialize(state);
    FileService.writeProjectConfig(rootDir, project ?? '', yamlStr);
    _hasUnsavedChanges = false;
  }

  /// Alias for saving to disk
  Future<void> saveToDisk() async {
    await save();
  }

  /// Reverts in-memory modifications back to the disk version
  void revert() {
    loadFromDisk();
  }

  Future<void> saveRawYaml(String yamlStr) async {
    FileService.writeProjectConfig(rootDir, project ?? '', yamlStr);
    state = YamlConfigParser.parse(yamlStr);
    _hasUnsavedChanges = false;
  }
}
