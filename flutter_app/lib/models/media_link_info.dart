class MediaLinkInfo {
  final bool success;
  final String rawUrl;
  final String title;
  final double duration;
  final String thumbnailUrl;
  final String streamUrl;
  final String? audioUrl;
  final Map<String, String>? httpHeaders;
  final String? error;
  final int? sizeBytes;

  const MediaLinkInfo({
    required this.success,
    required this.rawUrl,
    this.title = '',
    this.duration = 0.0,
    this.thumbnailUrl = '',
    this.streamUrl = '',
    this.audioUrl,
    this.httpHeaders,
    this.error,
    this.sizeBytes,
  });

  factory MediaLinkInfo.fromJson(Map<String, dynamic> json) {
    Map<String, String>? headers;
    if (json['http_headers'] is Map) {
      headers = (json['http_headers'] as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    }

    return MediaLinkInfo(
      success: json['success'] as bool? ?? false,
      rawUrl: json['raw_url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      thumbnailUrl: json['thumbnail'] as String? ?? '',
      streamUrl: json['stream_url'] as String? ?? '',
      audioUrl: json['audio_url'] as String?,
      httpHeaders: headers,
      error: json['error'] as String?,
      sizeBytes: json['size_bytes'] as int?,
    );
  }

  factory MediaLinkInfo.error(String rawUrl, String errorMessage) {
    return MediaLinkInfo(
      success: false,
      rawUrl: rawUrl,
      error: errorMessage,
    );
  }

  String get formattedDuration {
    if (duration <= 0) return '';
    final m = (duration ~/ 60).toString().padLeft(2, '0');
    final s = ((duration % 60).toInt()).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
