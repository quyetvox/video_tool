import 'dart:convert';
import 'package:http/http.dart' as http;

class AiTestResult {
  final bool success;
  final String message;
  final String? translatedSample;
  final int? latencyMs;
  final int? statusCode;

  const AiTestResult({
    required this.success,
    required this.message,
    this.translatedSample,
    this.latencyMs,
    this.statusCode,
  });
}

class AiConnectionTester {
  /// Test connectivity and translation with the configured AI provider
  static Future<AiTestResult> testConnection({
    required String providerType,
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    final cleanType = providerType.trim().toLowerCase();
    var cleanBaseUrl = baseUrl.trim();
    if (cleanBaseUrl.isEmpty) {
      if (cleanType == 'ollama') {
        cleanBaseUrl = 'http://localhost:11434';
      } else if (cleanType == 'deepseek') {
        cleanBaseUrl = 'https://api.deepseek.com/v1';
      } else if (cleanType == 'groq') {
        cleanBaseUrl = 'https://api.groq.com/openai/v1';
      } else if (cleanType == 'openrouter') {
        cleanBaseUrl = 'https://openrouter.ai/api/v1';
      } else if (cleanType == 'gemini') {
        cleanBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
      } else {
        cleanBaseUrl = 'https://api.openai.com/v1';
      }
    }

    // Strip trailing slash
    while (cleanBaseUrl.endsWith('/')) {
      cleanBaseUrl = cleanBaseUrl.substring(0, cleanBaseUrl.length - 1);
    }

    final stopwatch = Stopwatch()..start();

    try {
      if (cleanType == 'ollama') {
        // Ollama test via /api/generate or /api/chat
        final endpoint = cleanBaseUrl.endsWith('/api') ? '$cleanBaseUrl/generate' : '$cleanBaseUrl/api/generate';
        final uri = Uri.parse(endpoint);

        final headers = <String, String>{'Content-Type': 'application/json'};
        if (apiKey.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${apiKey.trim()}';
        }

        final body = jsonEncode({
          'model': model.trim().isNotEmpty ? model.trim() : 'gemma4:31b-cloud',
          'prompt': 'Translate "Hello World" into Vietnamese concisely. Reply with translated text only.',
          'stream': false,
        });

        final res = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 15));
        stopwatch.stop();

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final responseText = data['response']?.toString().trim() ?? 'OK';
          return AiTestResult(
            success: true,
            message: 'Kết nối Ollama thành công!',
            translatedSample: responseText,
            latencyMs: stopwatch.elapsedMilliseconds,
            statusCode: res.statusCode,
          );
        } else {
          return AiTestResult(
            success: false,
            message: 'Ollama trả về mã lỗi ${res.statusCode}: ${res.body}',
            latencyMs: stopwatch.elapsedMilliseconds,
            statusCode: res.statusCode,
          );
        }
      } else {
        // OpenAI-compatible endpoint (OpenAI, DeepSeek, Groq, OpenRouter, Gemini OpenAI endpoint, Custom)
        var endpoint = cleanBaseUrl;
        if (!endpoint.endsWith('/chat/completions')) {
          endpoint = '$endpoint/chat/completions';
        }
        final uri = Uri.parse(endpoint);

        final headers = <String, String>{
          'Content-Type': 'application/json',
        };
        if (apiKey.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${apiKey.trim()}';
        }

        final cleanModel = model.trim().isNotEmpty ? model.trim() : 'gpt-4o-mini';

        final body = jsonEncode({
          'model': cleanModel,
          'messages': [
            {'role': 'system', 'content': 'You are a professional translator. Translate into Vietnamese concisely.'},
            {'role': 'user', 'content': 'Translate: "Hello World"'}
          ],
          'temperature': 0.3,
          'max_tokens': 50,
        });

        final res = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 15));
        stopwatch.stop();

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final reply = data['choices']?[0]?['message']?['content']?.toString().trim() ?? 'OK';
          return AiTestResult(
            success: true,
            message: 'Kết nối AI Provider ($cleanType) thành công!',
            translatedSample: reply,
            latencyMs: stopwatch.elapsedMilliseconds,
            statusCode: res.statusCode,
          );
        } else {
          return AiTestResult(
            success: false,
            message: 'AI Provider trả về mã lỗi ${res.statusCode}: ${res.body}',
            latencyMs: stopwatch.elapsedMilliseconds,
            statusCode: res.statusCode,
          );
        }
      }
    } catch (e) {
      stopwatch.stop();
      return AiTestResult(
        success: false,
        message: 'Không thể kết nối đến $cleanBaseUrl: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}
