import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
import '../utils/yaml_config_parser.dart';
import '../utils/yaml_config_serializer.dart';
import 'file_service.dart';

class ConfigNotifier extends StateNotifier<AppConfig> {
  final String? project;
  final String rootDir;
  bool _hasUnsavedChanges = false;
  bool _isJustSaved = false;
  Timer? _saveResetTimer;

  ConfigNotifier({
    this.project,
    required this.rootDir,
  }) : super(AppConfig.defaults()) {
    loadFromDisk();
  }

  bool get hasUnsavedChanges => _hasUnsavedChanges;
  bool get isJustSaved => _isJustSaved;

  void loadFromDisk() {
    final yamlStr = FileService.readProjectConfig(rootDir, project ?? '');
    if (yamlStr.trim().isNotEmpty) {
      state = YamlConfigParser.parse(yamlStr);
    } else {
      state = AppConfig.defaults();
    }
    _hasUnsavedChanges = false;
    _isJustSaved = false;
  }

  /// Updates whole config in-memory only
  void updateConfig(AppConfig newConfig) {
    state = newConfig;
    _hasUnsavedChanges = true;
    _isJustSaved = false;
  }

  /// Updates state in-memory only (deferred saving)
  void setField(AppConfig Function(AppConfig current) updater) {
    state = updater(state);
    _hasUnsavedChanges = true;
    _isJustSaved = false;
  }

  /// Explicitly writes current configuration to disk
  Future<void> save() async {
    final yamlStr = YamlConfigSerializer.serialize(state);
    FileService.writeProjectConfig(rootDir, project ?? '', yamlStr);
    _hasUnsavedChanges = false;
    _isJustSaved = true;
    state = state.copyWith();

    _saveResetTimer?.cancel();
    _saveResetTimer = Timer(const Duration(milliseconds: 2000), () {
      _isJustSaved = false;
      state = state.copyWith();
    });
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
    _isJustSaved = true;

    _saveResetTimer?.cancel();
    _saveResetTimer = Timer(const Duration(milliseconds: 2000), () {
      _isJustSaved = false;
      state = state.copyWith();
    });
  }

  @override
  void dispose() {
    _saveResetTimer?.cancel();
    super.dispose();
  }
}
