import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Pure Dart Microsoft EdgeTTS Client (100% Native, Zero Python Dependency)
class EdgeTtsClient {
  static const String _trustedToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _wssUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=$_trustedToken';

  /// Synthesizes text to an MP3 file using Microsoft Edge Speech WebSocket.
  static Future<bool> synthesize({
    required String text,
    required File outputFile,
    String voice = 'vi-VN-HoaiMyNeural',
    double speedFactor = 1.0,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return false;

    // Calculate rate string for prosody
    final ratePercent = ((speedFactor - 1.0) * 100).round();
    final rateStr = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';

    // Generate random connection ID (32-char hex)
    final connectionId = _generateHex(32);
    final urlWithConn = '$_wssUrl&ConnectionId=$connectionId';

    final completer = Completer<bool>();
    final audioChunks = <Uint8List>[];

    try {
      final ws = await WebSocket.connect(
        urlWithConn,
        headers: {
          'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
        },
      ).timeout(const Duration(seconds: 10));

      final dateStr = DateTime.now().toUtc().toIso8601String();

      // 1. Send speech.config
      final configMsg =
          'X-Timestamp:$dateStr\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
      ws.add(configMsg);

      // 2. Send SSML request
      final escapedText = cleanText
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');

      final langCode = voice.split('-').take(2).join('-');
      final ssml =
          "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$langCode'>"
          "<voice name='$voice'>"
          "<prosody pitch='+0Hz' rate='$rateStr' volume='+0%'>"
          "$escapedText"
          "</prosody>"
          "</voice>"
          "</speak>";

      final requestId = _generateHex(32);
      final ssmlMsg =
          'X-RequestId:$requestId\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:$dateStr\r\nPath:ssml\r\n\r\n$ssml';
      ws.add(ssmlMsg);

      ws.listen(
        (data) {
          if (data is String) {
            if (data.contains('Path:turn.end')) {
              ws.close();
              if (!completer.isCompleted) {
                completer.complete(true);
              }
            }
          } else if (data is List<int>) {
            // Binary audio frame from EdgeTTS WebSocket:
            // 2 bytes header length (Big Endian) + headers ASCII ("Path:audio\r\n...") + binary audio payload
            if (data.length > 2) {
              final headerLen = (data[0] << 8) | data[1];
              if (data.length > 2 + headerLen) {
                final payload = Uint8List.fromList(data.sublist(2 + headerLen));
                if (payload.isNotEmpty) {
                  audioChunks.add(payload);
                }
              }
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(audioChunks.isNotEmpty);
        },
      );

      final success = await completer.future.timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (success && audioChunks.isNotEmpty) {
        final totalLen = audioChunks.fold<int>(0, (sum, c) => sum + c.length);
        final combined = Uint8List(totalLen);
        var offset = 0;
        for (final c in audioChunks) {
          combined.setRange(offset, offset + c.length, c);
          offset += c.length;
        }

        outputFile.writeAsBytesSync(combined);
        return outputFile.existsSync() && outputFile.lengthSync() > 100;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static String _generateHex(int length) {
    const chars = '0123456789abcdef';
    final random = DateTime.now().microsecondsSinceEpoch;
    final sb = StringBuffer();
    for (int i = 0; i < length; i++) {
      sb.write(chars[(random + i * 13) % chars.length]);
    }
    return sb.toString();
  }
}
