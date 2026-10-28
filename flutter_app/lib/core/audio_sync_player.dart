import 'dart:io';
import 'package:media_kit/media_kit.dart';
import '../models/studio_state.dart';

/// AudioSyncPlayer coordinates multi-track audio playback alongside the main video player.
class AudioSyncPlayer {
  final Map<String, Player> _trackPlayers = {};
  final Map<String, String?> _currentTrackPaths = {};

  List<StudioAudioTrack> _audioTracks = const [StudioAudioTrack(id: 'track-au-1', name: 'Âm thanh 1')];
  List<AudioClip> _audioClips = [];
  AudioMixState _mixState = const AudioMixState();
  bool _isPlaying = false;

  AudioSyncPlayer() {
    _trackPlayers['track-au-1'] = Player();
  }

  void updateTracks(List<StudioAudioTrack> tracks) {
    _audioTracks = tracks;
    final activeIds = tracks.map((t) => t.id).toSet();
    final toRemove = _trackPlayers.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in toRemove) {
      _trackPlayers[id]?.dispose();
      _trackPlayers.remove(id);
      _currentTrackPaths.remove(id);
    }
    for (final track in tracks) {
      _trackPlayers.putIfAbsent(track.id, () => Player());
    }
    _applyVolumes();
  }

  void updateClips(List<AudioClip> clips) {
    _audioClips = clips;
    _applyVolumes();
  }

  void updateMixState(AudioMixState mix) {
    _mixState = mix;
    _applyVolumes();
  }

  void _applyVolumes() {
    for (final track in _audioTracks) {
      final player = _trackPlayers[track.id];
      if (player == null) continue;

      if (track.muted || _mixState.musicMuted) {
        player.setVolume(0);
        continue;
      }

      final curPath = _currentTrackPaths[track.id];
      final activeClip = _audioClips.where((a) => a.trackId == track.id && a.fullPath == curPath).firstOrNull;
      final clipFactor = (activeClip?.muted == true) ? 0.0 : ((activeClip?.volume ?? 100) / 100.0);
      final trackFactor = track.volume / 100.0;
      // Backward compatibility: nếu draft cũ lưu musicVolume ở footer và clip vẫn ở 100%
      final masterFactor = (activeClip != null && activeClip.volume == 100 && _mixState.musicVolume != 100 && _mixState.musicVolume > 0)
          ? (_mixState.musicVolume / 100.0)
          : 1.0;
      final effective = (clipFactor * trackFactor * masterFactor * 100.0).clamp(0.0, 200.0);
      player.setVolume(effective);
    }
  }

  void syncPosition(double currentSec, bool isPlaying) {
    _isPlaying = isPlaying;

    for (final track in _audioTracks) {
      final player = _trackPlayers.putIfAbsent(track.id, () => Player());

      final activeClip = _audioClips.where((a) => a.trackId == track.id && currentSec >= a.start && currentSec <= a.end).firstOrNull;
      if (activeClip != null && File(activeClip.fullPath).existsSync()) {
        final offsetSec = currentSec - activeClip.start;
        final curPath = _currentTrackPaths[track.id];
        if (curPath != activeClip.fullPath) {
          _currentTrackPaths[track.id] = activeClip.fullPath;
          _applyVolumes();
          player.open(Media(activeClip.fullPath), play: false).then((_) {
            _applyVolumes();
            player.seek(Duration(milliseconds: (offsetSec * 1000).round()));
            if (_isPlaying) player.play();
          });
        } else {
          _applyVolumes();
          if (_isPlaying) {
            player.play();
          } else {
            player.pause();
          }
        }
      } else {
        if (_currentTrackPaths[track.id] != null) {
          player.pause();
          _currentTrackPaths[track.id] = null;
        }
      }
    }
  }

  void seek(double sec) {
    _currentTrackPaths.clear();
    syncPosition(sec, _isPlaying);
  }

  void pause() {
    _isPlaying = false;
    for (final p in _trackPlayers.values) {
      p.pause();
    }
  }

  void clearSession() {
    _isPlaying = false;
    for (final p in _trackPlayers.values) {
      p.pause();
      p.dispose();
    }
    _trackPlayers.clear();
    _currentTrackPaths.clear();
    _audioTracks = const [StudioAudioTrack(id: 'track-au-1', name: 'Âm thanh 1')];
    _audioClips = [];
    _mixState = const AudioMixState();
    _trackPlayers['track-au-1'] = Player();
  }

  void dispose() {
    for (final p in _trackPlayers.values) {
      p.dispose();
    }
    _trackPlayers.clear();
    _currentTrackPaths.clear();
  }
}
