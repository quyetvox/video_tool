import 'dart:async';
import 'package:media_kit/media_kit.dart';
import '../models/studio_state.dart';

/// VirtualTimelineController coordinates seamless playback across CUT and SPLIT segments.
/// Whenever the player enters a junk cut region, it instantly seeks forward to the end of that region.
class VirtualTimelineController {
  final Player player;
  StreamSubscription<Duration>? _positionSub;
  List<CutSegment> _cutSegments = [];
  List<SplitSegment> _splitSegments = [];
  StudioToolMode _mode = StudioToolMode.cut;
  bool _isSeeking = false;
  double _lastSeekSec = -1.0;

  VirtualTimelineController({required this.player}) {
    _positionSub = player.stream.position.listen(_onPositionUpdate);
  }

  void updateState({
    required StudioToolMode mode,
    required List<CutSegment> cutSegments,
    required List<SplitSegment> splitSegments,
  }) {
    _mode = mode;
    _cutSegments = cutSegments;
    _splitSegments = splitSegments;
  }

  List<SplitSegment> get splitSegments => _splitSegments;

  void _onPositionUpdate(Duration pos) {
    if (_isSeeking) return;
    final currentSec = pos.inMilliseconds / 1000.0;

    if (_mode == StudioToolMode.cut && _cutSegments.isNotEmpty) {
      for (final cut in _cutSegments) {
        if (currentSec >= cut.start && currentSec < cut.end) {
          // If we haven't already jumped past this cut
          if ((_lastSeekSec - cut.end).abs() > 0.3) {
            _isSeeking = true;
            _lastSeekSec = cut.end;
            player.seek(Duration(milliseconds: (cut.end * 1000).round())).then((_) {
              Future.delayed(const Duration(milliseconds: 150), () {
                _isSeeking = false;
              });
            });
          }
          return;
        }
      }
    }
  }

  void dispose() {
    _positionSub?.cancel();
  }
}
