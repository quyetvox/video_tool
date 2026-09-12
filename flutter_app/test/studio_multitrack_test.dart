import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/studio_state_notifier.dart';
import 'package:sub_video_desktop/models/studio_state.dart';

void main() {
  group('Studio Multitrack & Track Selection Tests', () {
    test('addAudioTrack creates new track and auto focuses selectedTrackId', () {
      final notifier = StudioStateNotifier();
      final initialCount = notifier.state.audioTracks.length;

      notifier.addAudioTrack();

      expect(notifier.state.audioTracks.length, initialCount + 1);
      final newTrack = notifier.state.audioTracks.last;
      expect(notifier.state.selectedTrackId, newTrack.id);
    });

    test('addOverlayTrack creates new track and auto focuses selectedTrackId', () {
      final notifier = StudioStateNotifier();
      final initialCount = notifier.state.overlayTracks.length;

      notifier.addOverlayTrack();

      expect(notifier.state.overlayTracks.length, initialCount + 1);
      final newTrack = notifier.state.overlayTracks.first;
      expect(notifier.state.selectedTrackId, newTrack.id);
    });

    test('addAudioClip with invalid trackId falls back to selectedTrackId', () {
      final notifier = StudioStateNotifier();
      notifier.addAudioTrack();
      final selectedId = notifier.state.selectedTrackId;
      expect(selectedId, isNotNull);

      // Add a clip with legacy/invalid trackId 'music'
      notifier.addAudioClip(
        const AudioClip(
          id: 'clip_legacy_1',
          trackId: 'music',
          name: 'bgm.mp3',
          fullPath: '/path/bgm.mp3',
          start: 0,
          end: 10,
        ),
      );

      final addedClip = notifier.state.audioClips.firstWhere((c) => c.id == 'clip_legacy_1');
      expect(addedClip.trackId, selectedId);
      expect(notifier.state.selectedClipId, 'clip_legacy_1');
    });

    test('addOverlayClip with invalid trackId falls back to selectedTrackId', () {
      final notifier = StudioStateNotifier();
      notifier.addOverlayTrack();
      final selectedId = notifier.state.selectedTrackId;
      expect(selectedId, isNotNull);

      // Add overlay with non-existent trackId
      notifier.addOverlayClip(
        const OverlayClip(
          id: 'ov_legacy_1',
          trackId: 'non_existent_track',
          name: 'logo.png',
          imagePath: '/path/logo.png',
          start: 0,
          end: 5,
        ),
      );

      final addedClip = notifier.state.overlayClips.firstWhere((c) => c.id == 'ov_legacy_1');
      expect(addedClip.trackId, selectedId);
      expect(notifier.state.selectedClipId, 'ov_legacy_1');
    });

    test('removeAudioTrack clears selectedTrackId if it matches removed track', () {
      final notifier = StudioStateNotifier();
      notifier.addAudioTrack();
      final createdTrackId = notifier.state.selectedTrackId!;

      notifier.removeAudioTrack(createdTrackId);
      expect(notifier.state.selectedTrackId, isNull);
    });

    test('removeOverlayTrack clears selectedTrackId if it matches removed track', () {
      final notifier = StudioStateNotifier();
      notifier.addOverlayTrack();
      final createdTrackId = notifier.state.selectedTrackId!;

      notifier.removeOverlayTrack(createdTrackId);
      expect(notifier.state.selectedTrackId, isNull);
    });

    test('setAudioClipVolume updates volume and clamps within 0..200', () {
      final notifier = StudioStateNotifier();
      notifier.addAudioClip(
        const AudioClip(
          id: 'test_clip_vol',
          trackId: 'track_1',
          name: 'audio.mp3',
          fullPath: '/audio.mp3',
          start: 0,
          end: 10,
          volume: 100,
        ),
      );

      notifier.setAudioClipVolume('test_clip_vol', 75);
      expect(notifier.state.audioClips.firstWhere((c) => c.id == 'test_clip_vol').volume, 75);

      // Clamp test > 200
      notifier.setAudioClipVolume('test_clip_vol', 250);
      expect(notifier.state.audioClips.firstWhere((c) => c.id == 'test_clip_vol').volume, 200);

      // Clamp test < 0
      notifier.setAudioClipVolume('test_clip_vol', -30);
      expect(notifier.state.audioClips.firstWhere((c) => c.id == 'test_clip_vol').volume, 0);
    });

    test('toggleAudioClipMute toggles muted flag', () {
      final notifier = StudioStateNotifier();
      notifier.addAudioClip(
        const AudioClip(
          id: 'test_clip_mute',
          trackId: 'track_1',
          name: 'audio.mp3',
          fullPath: '/audio.mp3',
          start: 0,
          end: 10,
          muted: false,
        ),
      );

      notifier.toggleAudioClipMute('test_clip_mute');
      expect(notifier.state.audioClips.firstWhere((c) => c.id == 'test_clip_mute').muted, isTrue);

      notifier.toggleAudioClipMute('test_clip_mute');
      expect(notifier.state.audioClips.firstWhere((c) => c.id == 'test_clip_mute').muted, isFalse);
    });
  });
}

