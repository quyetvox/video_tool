import 'dart:io';
import 'package:yaml/yaml.dart';

/// Mapping from flat config keys to nested dot-paths
const Map<String, String> flatToNestedMap = {
  // App
  'device': 'app.device',
  'target_lang': 'app.target_lang',
  'secondary_lang': 'app.secondary_lang',
  'ocr_only': 'app.ocr_only',
  'video_bitrate': 'app.video_bitrate',
  'output_suffix': 'app.output_suffix',
  'workspace_dir': 'app.workspace_dir',
  'output_dir': 'app.output_dir',
  'duration': 'app.duration',

  // ASR
  'asr': 'asr.engine',
  'asr_model': 'asr.model',

  // OCR
  'ocr': 'ocr.engine',
  'ocr_num_workers': 'ocr.num_workers',
  'ocr_mode': 'ocr.mode',
  'ocr_diff_threshold': 'ocr.diff_threshold',
  'diff_threshold': 'ocr.diff_threshold',
  'ocr_diff_step': 'ocr.diff_step',
  'diff_step': 'ocr.diff_step',
  'subtitle_detect_start_sec': 'ocr.detect_start_sec',
  'subtitle_detect_duration_sec': 'ocr.detect_duration_sec',

  // Inpaint
  'inpaint': 'inpaint.engine',
  'inpaint_engine': 'inpaint.engine',
  'inpaint_show_box': 'inpaint.show_box',
  'inpaint_method': 'inpaint.method',
  'inpaint_color': 'inpaint.color',
  'inpaint_region': 'inpaint.region',
  'blur_radius': 'inpaint.blur_radius',
  'inpaint_blur_radius': 'inpaint.blur_radius',
  'blur_box_padding_y': 'inpaint.padding_y',
  'inpaint_padding_y': 'inpaint.padding_y',
  'padding_y': 'inpaint.padding_y',
  'inpaint_box_bg_color': 'inpaint.box.bg_color',
  'inpaint_box_bg_opacity': 'inpaint.box.bg_opacity',
  'inpaint_box_border_color': 'inpaint.box.border_color',
  'inpaint_box_border_width': 'inpaint.box.border_width',
  'inpaint_box_border_radius': 'inpaint.box.border_radius',

  // Subtitle
  'show_subtitle': 'subtitle.show',
  'subtitle_show_primary': 'subtitle.show_primary',
  'subtitle_region': 'subtitle.region',
  'subtitle_primary_region': 'subtitle.region',
  'subtitle_order': 'subtitle.order',
  'subtitle_box_split': 'subtitle.box_split',
  'subtitle_box_gap': 'subtitle.box_gap',
  'subtitle_font_name': 'subtitle.font_name',
  'subtitle_fonts_dir': 'subtitle.fonts_dir',
  'fonts_dir': 'subtitle.fonts_dir',
  'subtitle_font_color': 'subtitle.font_color',
  'subtitle_outline_color': 'subtitle.outline_color',
  'subtitle_font_size': 'subtitle.font_size',
  'subtitle_char_rate': 'subtitle.char_rate',
  'subtitle_safety_margin': 'subtitle.safety_margin',
  'subtitle_fill_gap': 'subtitle.fill_gap',
  'subtitle_max_gap_fill': 'subtitle.max_gap_fill',
  'subtitle_box_lead_in': 'subtitle.box_lead_in',
  'subtitle_box_lead_out': 'subtitle.box_lead_out',
  'subtitle_secondary_show': 'subtitle.secondary.show',
  'subtitle_secondary_region': 'subtitle.secondary.region',
  'subtitle_secondary_font_name': 'subtitle.secondary.font_name',
  'subtitle_secondary_font_size_scale': 'subtitle.secondary.font_size_scale',
  'subtitle_secondary_font_color': 'subtitle.secondary.font_color',
  'subtitle_secondary_outline_color': 'subtitle.secondary.outline_color',

  // Watermark
  'watermark_enabled': 'watermark.enabled',
  'watermark_enable': 'watermark.enabled',
  'watermark_region': 'watermark.region',
  'watermark_image': 'watermark.image',
  'watermark_text': 'watermark.text',
  'watermark_font_name': 'watermark.font_name',
  'watermark_font_color': 'watermark.font_color',
  'watermark_opacity': 'watermark.opacity',
  'watermark_blur_bg': 'watermark.blur_bg',

  // TTS
  'tts': 'tts.engine',
  'tts_voice': 'tts.voice',
  'tts_speed_factor': 'tts.speed_factor',
  'enable_gender_tts': 'tts.enable_gender',
  'tts_voice_male': 'tts.voice_male',
  'tts_voice_female': 'tts.voice_female',

  // Audio
  'tts_voice_volume': 'audio.volumes.tts_voice',
  'original_voice_volume': 'audio.volumes.original_voice',
  'music_volume': 'audio.volumes.music',
  'background_music_volume': 'audio.volumes.music',
  'ambient_volume': 'audio.volumes.ambient',
  'noise_reduction_strength': 'audio.filters.noise_reduction_strength',
  'ambient_split_threshold': 'audio.filters.ambient_split_threshold',

  // Translator
  'translator': 'translator.type',
  'translator_model': 'translator.model',
  'translator_api_key': 'translator.api_key',
  'translator_base_url': 'translator.base_url',
  'translator_batch_size': 'translator.batch_size',

  // Metadata
  'enable_metadata_gen': 'metadata.enabled',
  'metadata_hashtags_count': 'metadata.hashtags_count',
};

/// Smart Configuration Dictionary supporting hierarchical dot paths & flat aliases.
class ConfigDict implements Map<String, dynamic> {
  final Map<String, dynamic> _map;

  ConfigDict([Map<String, dynamic>? initial]) : _map = <String, dynamic>{} {
    if (initial != null) {
      deepMerge(initial);
    }
  }

  static ConfigDict fromYamlFile(File file) {
    if (!file.existsSync()) return ConfigDict();
    try {
      final content = file.readAsStringSync();
      final raw = loadYaml(content);
      if (raw is YamlMap) {
        return ConfigDict(_fromYamlMap(raw));
      }
    } catch (_) {}
    return ConfigDict();
  }

  static dynamic _cleanValue(dynamic v) {
    if (v is YamlMap) {
      return ConfigDict(_fromYamlMap(v));
    } else if (v is YamlList) {
      return v.map(_cleanValue).toList();
    } else if (v is Map) {
      return ConfigDict(v.map((k, val) => MapEntry(k.toString(), _cleanValue(val))));
    } else if (v is List) {
      return v.map(_cleanValue).toList();
    }
    return v;
  }

  static Map<String, dynamic> _fromYamlMap(YamlMap ym) {
    final res = <String, dynamic>{};
    for (final entry in ym.entries) {
      res[entry.key.toString()] = _cleanValue(entry.value);
    }
    return res;
  }

  /// Create a ConfigDict from Yaml content
  factory ConfigDict.fromYaml(String yamlContent) {
    final loaded = loadYaml(yamlContent);
    if (loaded is YamlMap) {
      return ConfigDict(_fromYamlMap(loaded));
    }
    return ConfigDict();
  }

  dynamic _getByDotPath(String dotPath) {
    final parts = dotPath.split('.');
    dynamic curr = _map;
    for (final part in parts) {
      if (curr is! Map || !curr.containsKey(part)) {
        return null;
      }
      curr = curr[part];
    }
    return curr;
  }

  /// Get value with smart fallback
  dynamic get(String key, [dynamic defaultValue]) {
    // 1. Inpaint Region Smart Lookup
    if (key == 'inpaint_region' || key == 'inpaint.region') {
      final v1 = _getByDotPath('inpaint.region');
      if (v1 is List && v1.length == 4) return v1;
      final v2 = _getByDotPath('inpaint.inpaint_region');
      if (v2 is List && v2.length == 4) return v2;
      if (_map.containsKey('inpaint_region') && _map['inpaint_region'] is List && (_map['inpaint_region'] as List).length == 4) {
        return _map['inpaint_region'];
      }
      if (_map.containsKey('inpaint') && _map['inpaint'] is List && (_map['inpaint'] as List).length == 4) {
        return _map['inpaint'];
      }
      return defaultValue;
    }

    // 2. Inpaint Engine Smart Lookup
    if (key == 'inpaint' || key == 'inpaint.engine' || key == 'inpaint_engine') {
      final val = _getByDotPath('inpaint.engine');
      if (val is String && val.trim().isNotEmpty) return val.trim();
      if (_map.containsKey('inpaint') && _map['inpaint'] is String && (_map['inpaint'] as String).trim().isNotEmpty) {
        return (_map['inpaint'] as String).trim();
      }
      return defaultValue ?? 'box_color';
    }

    // 3. Known flat alias to nested dot-path
    if (flatToNestedMap.containsKey(key)) {
      final val = _getByDotPath(flatToNestedMap[key]!);
      if (val != null) return val;
    }

    // 4. Dot-notation path
    if (key.contains('.')) {
      final val = _getByDotPath(key);
      if (val != null) return val;
    }

    // 5. Direct key in dictionary
    if (_map.containsKey(key) && _map[key] != null) {
      return _map[key];
    }

    return defaultValue;
  }

  /// Recursive deep merge of another map
  void deepMerge(Map<String, dynamic> other) {
    for (final entry in other.entries) {
      final k = entry.key;
      final v = _cleanValue(entry.value);

      if (_map.containsKey(k) && _map[k] is Map && v is Map) {
        if (_map[k] is! ConfigDict) {
          _map[k] = ConfigDict(_map[k] as Map<String, dynamic>);
        }
        (_map[k] as ConfigDict).deepMerge(Map<String, dynamic>.from(v));
      } else {
        _map[k] = v;
      }
    }
  }

  ConfigDict clone() {
    final cloned = ConfigDict();
    cloned.deepMerge(_map);
    return cloned;
  }

  @override
  dynamic operator [](Object? key) {
    if (key is! String) return null;
    return get(key);
  }

  @override
  void operator []=(String key, dynamic value) {
    _map[key] = _cleanValue(value);
  }

  @override
  void clear() => _map.clear();

  @override
  bool containsKey(Object? key) {
    if (key is! String) return false;
    if (_map.containsKey(key)) return true;
    if (key.contains('.')) return _getByDotPath(key) != null;
    if (flatToNestedMap.containsKey(key)) return _getByDotPath(flatToNestedMap[key]!) != null;
    return false;
  }

  @override
  bool containsValue(Object? value) => _map.containsValue(value);

  @override
  Iterable<MapEntry<String, dynamic>> get entries => _map.entries;

  @override
  bool get isEmpty => _map.isEmpty;

  @override
  bool get isNotEmpty => _map.isNotEmpty;

  @override
  Iterable<String> get keys => _map.keys;

  @override
  int get length => _map.length;

  @override
  dynamic remove(Object? key) => _map.remove(key);

  @override
  Iterable<dynamic> get values => _map.values;

  @override
  void addAll(Map<String, dynamic> other) => deepMerge(other);

  @override
  void addEntries(Iterable<MapEntry<String, dynamic>> newEntries) {
    for (final e in newEntries) {
      this[e.key] = e.value;
    }
  }

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(String key, dynamic value) transform) {
    return _map.map(transform);
  }

  @override
  dynamic putIfAbsent(String key, dynamic Function() ifAbsent) {
    if (!containsKey(key)) {
      final v = ifAbsent();
      this[key] = v;
      return v;
    }
    return this[key];
  }

  @override
  void removeWhere(bool Function(String key, dynamic value) test) {
    _map.removeWhere(test);
  }

  @override
  dynamic update(String key, dynamic Function(dynamic value) update, {dynamic Function()? ifAbsent}) {
    if (containsKey(key)) {
      final v = update(this[key]);
      this[key] = v;
      return v;
    } else if (ifAbsent != null) {
      final v = ifAbsent();
      this[key] = v;
      return v;
    }
    throw ArgumentError.value(key, 'key', 'Key not in map.');
  }

  @override
  void updateAll(dynamic Function(String key, dynamic value) update) {
    for (final k in _map.keys) {
      _map[k] = update(k, _map[k]);
    }
  }

  @override
  Map<RK, RV> cast<RK, RV>() => _map.cast<RK, RV>();

  @override
  void forEach(void Function(String key, dynamic value) action) {
    _map.forEach(action);
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_map);
}
