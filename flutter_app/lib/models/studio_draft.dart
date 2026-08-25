import 'studio_state.dart';

class StudioDraft {
  final String id;
  final String name;
  final String videoPath;
  final String videoStem;
  final DateTime updatedAt;
  final StudioToolMode toolMode;
  final StudioSnapshot snapshot;

  const StudioDraft({
    required this.id,
    required this.name,
    required this.videoPath,
    required this.videoStem,
    required this.updatedAt,
    required this.toolMode,
    required this.snapshot,
  });

  int get overlayCount => snapshot.overlayClips.length;
  int get audioCount => snapshot.audioClips.length;
  int get subtitleCount => snapshot.subtitles.length;
  int get cutCount => snapshot.cutSegments.length;
  int get splitCount => snapshot.splitSegments.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'videoPath': videoPath,
        'videoStem': videoStem,
        'updatedAt': updatedAt.toIso8601String(),
        'toolMode': toolMode.name,
        'snapshot': snapshot.toJson(),
      };

  factory StudioDraft.fromJson(Map<String, dynamic> json) {
    return StudioDraft(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Bản nháp',
      videoPath: json['videoPath'] as String? ?? '',
      videoStem: json['videoStem'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      toolMode: StudioToolMode.values.firstWhere(
        (m) => m.name == json['toolMode'],
        orElse: () => StudioToolMode.composite,
      ),
      snapshot: StudioSnapshot.fromJson(json['snapshot'] as Map<String, dynamic>? ?? {}),
    );
  }
}
