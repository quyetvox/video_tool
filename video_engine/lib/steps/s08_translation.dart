import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';

class StepTranslation extends StepBase {
  @override
  String get stepId => 's08_translation';

  @override
  List<String> get dependsOn => const ['s07_transcript_merge'];

  @override
  List<String> get stepConfigKeys => const [
        'translator',
        'translator_model',
        'target_lang',
        'secondary_lang',
      ];

  static final RegExp _zhPattern = RegExp(r'[\u4e00-\u9fff]');

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final transcriptInfo = jobState.getStepOutput('s07_transcript_merge') ?? {};
    final transcriptFile = transcriptInfo['transcript_file'] as String?;
    final outFile = File(p.join(workspace.path, 's08_translation.json'));

    if (transcriptFile == null || !File(transcriptFile).existsSync()) {
      outFile.writeAsStringSync('[]');
      return {'translation_file': outFile.path, 'segment_count': 0};
    }

    final segments = (jsonDecode(File(transcriptFile).readAsStringSync()) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (segments.isEmpty) {
      outFile.writeAsStringSync('[]');
      return {'translation_file': outFile.path, 'segment_count': 0};
    }

    final appCfg = config['app'] is Map ? config['app'] as Map : {};
    final targetLang = (config['target_lang'] ?? appCfg['target_lang'] ?? 'vi').toString().trim();
    final secondaryLang = (config['secondary_lang'] ?? appCfg['secondary_lang'] ?? '').toString().trim();
    final isBilingual = secondaryLang.isNotEmpty && secondaryLang.toLowerCase() != targetLang.toLowerCase();

    final translatorObj = config['translator'] ?? appCfg['translator'];
    String host = 'http://localhost:11434';
    String model = 'gemma4:31b-cloud';
    int batchSize = 20;
    String apiKey = '';

    if (translatorObj is Map) {
      host = (translatorObj['base_url'] ?? translatorObj['host'] ?? 'http://localhost:11434').toString();
      model = (translatorObj['model'] ?? 'gemma4:31b-cloud').toString();
      batchSize = (translatorObj['batch_size'] as num?)?.toInt() ?? 20;
      apiKey = (translatorObj['api_key'] ?? '').toString();
    } else if (translatorObj is String && translatorObj.isNotEmpty) {
      host = (config['translator_base_url'] ?? 'http://localhost:11434').toString();
      model = (config['translator_model'] ?? 'gemma4:31b-cloud').toString();
      batchSize = (config['translator_batch_size'] as num?)?.toInt() ?? 20;
      apiKey = (config['translator_api_key'] ?? '').toString();
    }

    host = host.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final translatedSegments = <Map<String, dynamic>>[];

    // --- Fast Pass 1: Lightweight Global Context & Character Glossary ---
    String globalContext = '';
    Map<String, dynamic> extractedMeta = {};

    if (segments.length > 5) {
      try {
        final sampleText = segments.take(15).map((s) => s['text'] ?? '').where((t) => t.toString().trim().isNotEmpty).join('\n');
        if (sampleText.isNotEmpty) {
          extractedMeta = await _extractFastContext(
            sampleText: sampleText,
            host: host,
            model: model,
            headers: headers,
            targetLang: targetLang,
          );
          if (extractedMeta.containsKey('context') && extractedMeta['context'].toString().isNotEmpty) {
            globalContext = extractedMeta['context'].toString();
          }
        }
      } catch (_) {
        // Non-blocking fallback
      }
    }

    for (int i = 0; i < segments.length; i += batchSize) {
      final endIdx = (i + batchSize < segments.length) ? (i + batchSize) : segments.length;
      final batch = segments.sublist(i, endIdx);

      final payloadInput = <Map<String, dynamic>>[];
      for (int idx = 0; idx < batch.length; idx++) {
        payloadInput.add({
          'id': idx,
          'text': batch[idx]['text'] ?? '',
        });
      }

      final contextPrefix = globalContext.isNotEmpty
          ? "Context & Character Pronouns: $globalContext\nEnsure consistent pronouns and natural conversational tone across segments.\n"
          : "";

      String prompt;
      if (isBilingual) {
        prompt = '''You are a professional video subtitle translator.
$contextPrefix
Translate each subtitle text segment into TWO languages:
1. Primary target language: '$targetLang'
2. Secondary target language: '$secondaryLang'
Maintain 100% complete meaning, natural spoken flow, and emotional nuances. Do not omit important details.
Return strictly a JSON array of objects with keys 'id', 'text' (primary in $targetLang), and 'text_secondary' (secondary in $secondaryLang).
Do not add any additional explanation, markdown blocks, or commentary.

Input JSON: ${jsonEncode(payloadInput)}''';
      } else {
        prompt = '''You are a professional video subtitle translator.
$contextPrefix
Translate the following subtitle text segments into target language: '$targetLang'.
Maintain 100% complete meaning, natural spoken flow, and emotional nuances. Do not omit important details.
Return strictly a JSON array of objects with keys 'id' and 'text'.
Do not add any additional explanation, markdown blocks, or commentary.

Input JSON: ${jsonEncode(payloadInput)}''';
      }

      try {
        String responseText = '';
        if (host.contains('/v1')) {
          final uri = Uri.parse(host.endsWith('/v1') ? '$host/chat/completions' : '$host/v1/chat/completions');
          final resp = await http.post(
            uri,
            headers: headers,
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'temperature': 0.2,
            }),
          ).timeout(const Duration(seconds: 180));

          if (resp.statusCode == 200) {
            final resJson = jsonDecode(resp.body) as Map<String, dynamic>;
            final choices = resJson['choices'] as List? ?? [];
            if (choices.isNotEmpty) {
              responseText = choices[0]['message']?['content']?.toString() ?? '';
            }
          } else {
            throw HttpException('LLM returned status ${resp.statusCode}: ${resp.body}');
          }
        } else {
          final uri = Uri.parse('$host/api/generate');
          final resp = await http.post(
            uri,
            headers: headers,
            body: jsonEncode({
              'model': model,
              'prompt': prompt,
              'format': 'json',
              'stream': false,
            }),
          ).timeout(const Duration(seconds: 180));

          if (resp.statusCode == 200) {
            final resJson = jsonDecode(resp.body) as Map<String, dynamic>;
            responseText = resJson['response']?.toString() ?? '';
          } else {
            throw HttpException('Ollama returned status ${resp.statusCode}: ${resp.body}');
          }
        }

        String cleanJson = responseText.trim();
        if (cleanJson.startsWith('```json')) cleanJson = cleanJson.substring(7);
        if (cleanJson.startsWith('```')) cleanJson = cleanJson.substring(3);
        if (cleanJson.endsWith('```')) cleanJson = cleanJson.substring(0, cleanJson.length - 3);
        cleanJson = cleanJson.trim();

        dynamic parsed = jsonDecode(cleanJson);
        List<dynamic> translatedBatch = [];
        if (parsed is List) {
          translatedBatch = parsed;
        } else if (parsed is Map) {
          translatedBatch = (parsed['segments'] ?? parsed['items'] ?? parsed.values.firstWhere((v) => v is List, orElse: () => [])) as List;
        }

        final transMap = <int, Map<String, dynamic>>{};
        for (final item in translatedBatch) {
          if (item is Map && item.containsKey('id')) {
            final id = int.tryParse(item['id'].toString());
            if (id != null) {
              transMap[id] = Map<String, dynamic>.from(item);
            }
          }
        }

        for (int idx = 0; idx < batch.length; idx++) {
          final seg = Map<String, dynamic>.from(batch[idx]);
          final origText = seg['text']?.toString() ?? '';
          final itemRes = transMap[idx] ?? {};

          String rawTrans = itemRes['text']?.toString() ?? origText;
          String rawSec = itemRes['text_secondary']?.toString() ?? '';

          if (rawTrans.isEmpty || (targetLang != 'zh' && _zhPattern.hasMatch(rawTrans))) {
            rawTrans = await _translateFallbackGoogle(origText, targetLang);
          }

          seg['orig_text'] = origText;
          seg['translated_text'] = rawTrans.trim();
          seg['text_vi'] = rawTrans.trim();
          seg['text'] = rawTrans.trim();

          if (isBilingual) {
            if (rawSec.isEmpty || (secondaryLang != 'zh' && _zhPattern.hasMatch(rawSec))) {
              rawSec = await _translateFallbackGoogle(origText, secondaryLang);
            }
            seg['text_secondary'] = rawSec.trim();
            seg['secondary_text'] = rawSec.trim();
            seg['text_$secondaryLang'] = rawSec.trim();
          } else {
            seg.remove('text_secondary');
            seg.remove('secondary_text');
          }

          translatedSegments.add(seg);
        }
      } catch (e) {
        // Fallback for batch
        for (final item in batch) {
          final seg = Map<String, dynamic>.from(item);
          final origText = seg['text']?.toString() ?? '';

          final rawTrans = await _translateFallbackGoogle(origText, targetLang);
          seg['orig_text'] = origText;
          seg['translated_text'] = rawTrans.trim();
          seg['text_vi'] = rawTrans.trim();
          seg['text'] = rawTrans.trim();

          if (isBilingual) {
            final rawSec = await _translateFallbackGoogle(origText, secondaryLang);
            seg['text_secondary'] = rawSec.trim();
            seg['secondary_text'] = rawSec.trim();
            seg['text_$secondaryLang'] = rawSec.trim();
          } else {
            seg.remove('text_secondary');
            seg.remove('secondary_text');
          }

          translatedSegments.add(seg);
        }
      }
    }

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(translatedSegments),
      flush: true,
    );

    return {
      'translation_file': outFile.path,
      'target_lang': targetLang,
      'secondary_lang': secondaryLang,
      'segment_count': translatedSegments.length,
      'global_context': globalContext,
      'summary': extractedMeta['summary'] ?? '',
      'title': extractedMeta['title'] ?? '',
    };
  }

  /// Ultra-fast context extraction taking ~0.5s to establish character pronouns and story gist
  Future<Map<String, dynamic>> _extractFastContext({
    required String sampleText,
    required String host,
    required String model,
    required Map<String, String> headers,
    required String targetLang,
  }) async {
    final prompt = '''Analyze this short dialogue sample from a video. Identify the tone, main relationship, and appropriate pronouns in '$targetLang' (e.g. Anh-Em, Tôi-Bạn, etc.).
Return strictly a JSON object: {"context": "concise description of relation and pronouns", "title": "short catchy title in $targetLang", "summary": "1 sentence gist in $targetLang"}.
Do not add markdown or explanation.

Sample:
$sampleText''';

    try {
      String responseText = '';
      if (host.contains('/v1')) {
        final uri = Uri.parse(host.endsWith('/v1') ? '$host/chat/completions' : '$host/v1/chat/completions');
        final resp = await http.post(
          uri,
          headers: headers,
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0.1,
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final resJson = jsonDecode(resp.body) as Map<String, dynamic>;
          final choices = resJson['choices'] as List? ?? [];
          if (choices.isNotEmpty) {
            responseText = choices[0]['message']?['content']?.toString() ?? '';
          }
        }
      } else {
        final uri = Uri.parse('$host/api/generate');
        final resp = await http.post(
          uri,
          headers: headers,
          body: jsonEncode({
            'model': model,
            'prompt': prompt,
            'format': 'json',
            'stream': false,
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final resJson = jsonDecode(resp.body) as Map<String, dynamic>;
          responseText = resJson['response']?.toString() ?? '';
        }
      }

      String clean = responseText.trim();
      if (clean.startsWith('```json')) clean = clean.substring(7);
      if (clean.startsWith('```')) clean = clean.substring(3);
      if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
      clean = clean.trim();

      final parsed = jsonDecode(clean);
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
    } catch (_) {}

    return {};
  }

  Future<String> _translateFallbackGoogle(String text, String lang) async {
    if (text.trim().isEmpty) return text;
    try {
      final encoded = Uri.encodeComponent(text);
      final url = Uri.parse('https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$lang&dt=t&q=$encoded');
      final resp = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      }).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is List && data.isNotEmpty && data[0] is List) {
          final parts = (data[0] as List).map((part) => (part is List && part.isNotEmpty) ? part[0].toString() : '').join('');
          if (parts.trim().isNotEmpty) {
            return parts.trim();
          }
        }
      }
    } catch (_) {}
    return text;
  }
}
