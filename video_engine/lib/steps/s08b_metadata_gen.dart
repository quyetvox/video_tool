import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/job_state.dart';
import '../core/step_base.dart';

class StepMetadataGen extends StepBase {
  @override
  String get stepId => 's08b_metadata_gen';

  @override
  List<String> get dependsOn => const ['s08_translation'];

  @override
  List<String> get stepConfigKeys => const [
        'enable_metadata_gen',
        'metadata_hashtags_count',
        'target_lang',
        'translator',
        'translator_model',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final outFile = File(p.join(workspace.path, 's08b_metadata.json'));
    final isEnabled = config['enable_metadata_gen'] != false;

    if (!isEnabled) {
      final defaultData = {
        'title': '',
        'description': '',
        'hashtags': <String>[],
        'skipped': true,
      };
      outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(defaultData));
      return defaultData;
    }

    // 1. Persistent Cache Check: If metadata already generated and valid, reuse it
    if (outFile.existsSync()) {
      try {
        final cached = jsonDecode(outFile.readAsStringSync()) as Map<String, dynamic>;
        if (cached['title'] != null && cached['title'].toString().isNotEmpty) {
          return cached;
        }
      } catch (_) {}
    }

    // 2. Direct reuse of s08 summary & title
    final transInfo = jobState.getStepOutput('s08_translation') ?? {};
    final transFile = transInfo['translation_file'] as String?;
    String title = (transInfo['title'] ?? '').toString().trim();
    String description = (transInfo['summary'] ?? '').toString().trim();

    if (title.isEmpty || description.isEmpty) {
      String fullTranscript = '';
      if (transFile != null && File(transFile).existsSync()) {
        try {
          final segs = jsonDecode(File(transFile).readAsStringSync()) as List? ?? [];
          fullTranscript = segs.map((s) => s['translated_text'] ?? s['text'] ?? '').join(' ');
        } catch (_) {}
      }
      if (title.isEmpty) {
        title = fullTranscript.length > 60 ? '${fullTranscript.substring(0, 60)}...' : fullTranscript;
      }
      if (description.isEmpty) {
        description = fullTranscript;
      }
    }

    final data = {
      'title': title,
      'description': description,
      'hashtags': ['#SubVideoAI', '#AI', '#VideoTranslation'],
      'skipped': false,
    };

    outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );

    return data;
  }
}
