import 'package:intl/intl.dart';

class DouyinVideoItem {
  final int index;
  final String rawUrl;
  final String directUrl;
  final String filename;
  final String shortHash;
  final String? timestampStr;
  final String resolution;
  final String bitrateStr;
  final int bitrate;
  final bool isDownloaded;
  final String? localFilePath;

  const DouyinVideoItem({
    required this.index,
    required this.rawUrl,
    required this.directUrl,
    required this.filename,
    required this.shortHash,
    this.timestampStr,
    required this.resolution,
    required this.bitrateStr,
    this.bitrate = 0,
    this.isDownloaded = false,
    this.localFilePath,
  });

  /// Helper to parse a raw Douyin / CDN link and extract metadata
  static DouyinVideoItem? parse(String line, int idx, {List<String> existingSrcFiles = const []}) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final urlRegex = RegExp(r'https?://[^\s]+');
    final match = urlRegex.firstMatch(trimmed);
    if (match == null) return null;

    final url = match.group(0)!;
    String shortHash = 'video_${(idx + 1).toString().padLeft(3, '0')}';
    String filename = '$shortHash.mp4';
    String? timestampStr;
    String resolution = '1080p HD';
    String bitrateStr = '1.40 Mbps';
    int bitrate = 1400000;

    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathSegments.isNotEmpty) {
        final last = pathSegments.last;
        shortHash = last.length >= 8 ? last.substring(0, 8) : last;
      }

      // Check Snowflake ID from url regex
      final snMatch = RegExp(r'(?:video/|modal_id=|aweme_id=)(\d{18,20})').firstMatch(url);
      if (snMatch != null) {
        try {
          final bigId = BigInt.parse(snMatch.group(1)!);
          final tsSec = (bigId >> 32).toInt();
          if (tsSec > 1500000000 && tsSec < 2500000000) {
            final dt = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
            timestampStr = DateFormat('yyyyMMdd_HHmmss').format(dt);
            filename = '${timestampStr}_$shortHash.mp4';
          }
        } catch (_) {}
      }

      // Check URL query parameters
      if (uri.queryParameters.containsKey('br')) {
        final br = int.tryParse(uri.queryParameters['br'] ?? '') ?? 0;
        if (br > 0) {
          bitrate = br;
          final mbps = (br / 1000000.0).toStringAsFixed(2);
          bitrateStr = '${(br ~/ 1000)}k $mbps Mbps';
          if (br >= 1500000) {
            resolution = '1080p HD';
          } else if (br >= 1000000) {
            resolution = '720p HD';
          } else {
            resolution = 'SD 540p';
          }
        }
      }

      if (timestampStr == null) {
        final now = DateTime.now();
        timestampStr = DateFormat('yyyyMMdd_HHmmss').format(now);
        filename = '${timestampStr}_$shortHash.mp4';
      }
    } catch (_) {}

    // Check if file is already in src/
    bool isDownloaded = false;
    String? localPath;
    for (final src in existingSrcFiles) {
      if (src.contains(shortHash) || (timestampStr != null && src.contains(timestampStr))) {
        isDownloaded = true;
        localPath = src;
        break;
      }
    }

    return DouyinVideoItem(
      index: idx + 1,
      rawUrl: trimmed,
      directUrl: url,
      filename: filename,
      shortHash: shortHash,
      timestampStr: timestampStr,
      resolution: resolution,
      bitrateStr: bitrateStr,
      bitrate: bitrate,
      isDownloaded: isDownloaded,
      localFilePath: localPath,
    );
  }
}
