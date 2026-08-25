import 'dart:io';
import 'package:media_kit/media_kit.dart';
import '../models/studio_state.dart';

/// AudioSyncPlayer coordinates multi-track audio playback alongside the main video player.
class AudioSyncPlayer {
  final Player _musicPlayer = Player();
  final Player _sfxPlayer = Player();

  List<AudioClip> _audioClips = [];
  AudioMixState _mixState = const AudioMixState();
  bool _isPlaying = false;
  String? _currentMusicPath;
  String? _currentSfxPath;

  AudioSyncPlayer() {
    _applyVolumes();
  }

  void updateClips(List<AudioClip> clips) {
    _audioClips = clips;
  }

  void updateMixState(AudioMixState mix) {
    _mixState = mix;
    _applyVolumes();
  }

  void _applyVolumes() {
    // Music Player volume
    if (_mixState.musicMuted) {
      _musicPlayer.setVolume(0);
    } else {
      _musicPlayer.setVolume((_mixState.musicVolume).clamp(0, 200).toDouble());
    }

    // SFX Player volume
    if (_mixState.sfxMuted) {
      _sfxPlayer.setVolume(0);
    } else {
      _sfxPlayer.setVolume((_mixState.sfxVolume).clamp(0, 200).toDouble());
    }
  }

  void syncPosition(double currentSec, bool isPlaying) {
    _isPlaying = isPlaying;

    // 1. Check Music Clip
    final activeMusic = _audioClips.where((a) => a.trackId == 'music' && currentSec >= a.start && currentSec <= a.end).firstOrNull;
    if (activeMusic != null && File(activeMusic.fullPath).existsSync()) {
      final offsetSec = currentSec - activeMusic.start;
      if (_currentMusicPath != activeMusic.fullPath) {
        _currentMusicPath = activeMusic.fullPath;
        _musicPlayer.open(Media(activeMusic.fullPath), play: false).then((_) {
          _musicPlayer.seek(Duration(milliseconds: (offsetSec * 1000).round()));
          if (_isPlaying) _musicPlayer.play();
        });
      } else {
        if (_isPlaying) {
          _musicPlayer.play();
        } else {
          _musicPlayer.pause();
        }
      }
    } else {
      if (_currentMusicPath != null) {
        _musicPlayer.pause();
        _currentMusicPath = null;
      }
    }

    // 2. Check SFX Clip
    final activeSfx = _audioClips.where((a) => a.trackId == 'sfx' && currentSec >= a.start && currentSec <= a.end).firstOrNull;
    if (activeSfx != null && File(activeSfx.fullPath).existsSync()) {
      final offsetSec = currentSec - activeSfx.start;
      if (_currentSfxPath != activeSfx.fullPath) {
        _currentSfxPath = activeSfx.fullPath;
        _sfxPlayer.open(Media(activeSfx.fullPath), play: false).then((_) {
          _sfxPlayer.seek(Duration(milliseconds: (offsetSec * 1000).round()));
          if (_isPlaying) _sfxPlayer.play();
        });
      } else {
        if (_isPlaying) {
          _sfxPlayer.play();
        } else {
          _sfxPlayer.pause();
        }
      }
    } else {
      if (_currentSfxPath != null) {
        _sfxPlayer.pause();
        _currentSfxPath = null;
      }
    }
  }

  void seek(double sec) {
    _currentMusicPath = null;
    _currentSfxPath = null;
    syncPosition(sec, _isPlaying);
  }

  void pause() {
    _isPlaying = false;
    _musicPlayer.pause();
    _sfxPlayer.pause();
  }

  void dispose() {
    _musicPlayer.dispose();
    _sfxPlayer.dispose();
  }
}
