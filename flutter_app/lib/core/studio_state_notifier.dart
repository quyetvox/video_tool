import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../models/studio_state.dart';

class StudioStateNotifier extends StateNotifier<StudioSnapshot> {
  static const int maxHistory = 50;
  final List<StudioSnapshot> _history = [];
  int _historyIndex = -1;

  StudioStateNotifier()
      : super(StudioSnapshot(
          id: 'initial',
          label: 'Khởi tạo studio',
          time: DateFormat('HH:mm:ss').format(DateTime.now()),
        )) {
    _history.add(state);
    _historyIndex = 0;
  }

  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;
  List<StudioSnapshot> get history => List.unmodifiable(_history);
  int get historyIndex => _historyIndex;

  void recordAction(String label, StudioSnapshot nextState) {
    // If not at tail of history, truncate future redo steps
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    final stamped = nextState.copyWith(
      id: 'step_${DateTime.now().millisecondsSinceEpoch}',
      label: label,
      time: DateFormat('HH:mm:ss').format(DateTime.now()),
    );

    _history.add(stamped);
    if (_history.length > maxHistory) {
      _history.removeAt(0);
    }
    _historyIndex = _history.length - 1;
    state = stamped;
  }

  void undo() {
    if (!canUndo) return;
    _historyIndex--;
    state = _history[_historyIndex];
  }

  void redo() {
    if (!canRedo) return;
    _historyIndex++;
    state = _history[_historyIndex];
  }

  void restoreAt(int index) {
    if (index < 0 || index >= _history.length) return;
    _historyIndex = index;
    state = _history[_historyIndex];
  }

  void loadSnapshot(StudioSnapshot snapshot, {String? draftName}) {
    final label = draftName != null ? 'Nạp bản nháp: $draftName' : 'Khôi phục bản nháp';
    recordAction(label, snapshot);
  }

  void resetToEmpty() {
    recordAction('Tạo bản nháp mới (Trống)', StudioSnapshot(
      id: 'snap_${DateTime.now().millisecondsSinceEpoch}',
      label: 'Bản nháp mới',
      time: DateFormat('HH:mm:ss').format(DateTime.now()),
    ));
  }

  // === CUT MODE ACTIONS ===
  void setCutRange(double start, double end) {
    state = state.copyWith(
      currentJunkStart: start,
      currentJunkEnd: end,
    );
  }

  void toggleCutBoxVisible() {
    final next = !state.showCutBox;
    recordAction(
      next ? 'Hiện khung cắt rác' : 'Ẩn khung cắt rác',
      state.copyWith(showCutBox: next),
    );
  }

  void addCutSegment(double start, double end) {
    final seg = CutSegment(
      id: 'cut_${DateTime.now().millisecondsSinceEpoch}',
      start: start,
      end: end,
    );
    final nextList = [...state.cutSegments, seg];
    recordAction(
      'Thêm đoạn rác: ${start.toStringAsFixed(1)}s - ${end.toStringAsFixed(1)}s',
      state.copyWith(cutSegments: nextList),
    );
  }

  void removeCutSegment(String id) {
    final nextList = state.cutSegments.where((s) => s.id != id).toList();
    recordAction('Xoá đoạn rác', state.copyWith(cutSegments: nextList));
  }

  // === SPLIT MODE ACTIONS ===
  void addSplitAt(double splitTime, double totalDuration) {
    final cur = List<SplitSegment>.from(state.splitSegments);
    if (cur.isEmpty) {
      // First split creates 2 segments
      cur.add(SplitSegment(
        id: 'split_1',
        name: 'Đoạn 1',
        start: 0,
        end: splitTime,
      ));
      cur.add(SplitSegment(
        id: 'split_2',
        name: 'Đoạn 2',
        start: splitTime,
        end: totalDuration,
      ));
    } else {
      // Find segment containing splitTime
      final idx = cur.indexWhere((s) => splitTime > s.start && splitTime < s.end);
      if (idx != -1) {
        final target = cur[idx];
        final segA = SplitSegment(
          id: '${target.id}_a',
          name: '${target.name} (Phần 1)',
          start: target.start,
          end: splitTime,
        );
        final segB = SplitSegment(
          id: '${target.id}_b',
          name: '${target.name} (Phần 2)',
          start: splitTime,
          end: target.end,
        );
        cur.removeAt(idx);
        cur.insert(idx, segB);
        cur.insert(idx, segA);
      }
    }

    recordAction('Chia clip tại ${splitTime.toStringAsFixed(2)}s', state.copyWith(splitSegments: cur));
  }

  void removeSplitSegment(String id) {
    final next = state.splitSegments.where((s) => s.id != id).toList();
    recordAction('Xoá đoạn chia', state.copyWith(splitSegments: next));
  }

  // === MERGE MODE ACTIONS ===
  void addMergeItem(MergeItem item) {
    final next = [...state.mergePlaylist, item];
    recordAction('Thêm video vào danh sách ghép: ${item.name}', state.copyWith(mergePlaylist: next));
  }

  void removeMergeItem(String id) {
    final next = state.mergePlaylist.where((m) => m.id != id).toList();
    recordAction('Bỏ video khỏi danh sách ghép', state.copyWith(mergePlaylist: next));
  }

  void updateMergeItemDuration(String id, double duration) {
    final next = state.mergePlaylist.map((m) {
      if (m.id == id) {
        return MergeItem(
          id: m.id,
          name: m.name,
          fullPath: m.fullPath,
          sizeBytes: m.sizeBytes,
          duration: duration,
        );
      }
      return m;
    }).toList();
    state = state.copyWith(mergePlaylist: next);
  }

  void reorderMergeItem(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final next = List<MergeItem>.from(state.mergePlaylist);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    recordAction('Đổi thứ tự ghép video', state.copyWith(mergePlaylist: next));
  }

  // === CLEAR SESSION ACTIONS ===
  void clearCutSession() {
    recordAction('Làm mới session Cắt bỏ rác',
        state.copyWith(cutSegments: [], showCutBox: false));
  }

  void clearSplitSession() {
    recordAction('Làm mới session Chia clip',
        state.copyWith(splitSegments: []));
  }

  void clearMergeSession() {
    recordAction('Làm mới session Ghép video',
        state.copyWith(mergePlaylist: []));
  }

  void clearCompositeSession() {
    recordAction(
      'Làm mới session Biên tập đa lớp',
      state.copyWith(
        overlayClips: [],
        audioClips: [],
        subtitles: [],
        mixState: const AudioMixState(),
        subStyle: const SubStyle(),
        selectedClipId: null,
        clearSelectedClip: true,
      ),
    );
  }

  // === OVERLAY TRACK ACTIONS ===
  void addOverlayTrack() {
    final nextIdx = state.overlayTracks.length + 1;
    final track = OverlayTrack(
      id: 'track-ov-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Lớp phủ $nextIdx',
    );
    final next = [track, ...state.overlayTracks];
    recordAction('Thêm làn lớp phủ mới', state.copyWith(overlayTracks: next, selectedTrackId: track.id));
  }

  void removeOverlayTrack(String trackId) {
    final nextTracks = state.overlayTracks.where((t) => t.id != trackId).toList();
    final nextClips = state.overlayClips.where((c) => c.trackId != trackId).toList();
    final clearSelTrack = state.selectedTrackId == trackId;
    recordAction(
      'Xoá làn lớp phủ',
      state.copyWith(
        overlayTracks: nextTracks,
        overlayClips: nextClips,
        clearSelectedTrack: clearSelTrack,
      ),
    );
  }

  void toggleTrackVisible(String trackId) {
    final next = state.overlayTracks.map((t) {
      if (t.id == trackId) return t.copyWith(visible: !t.visible);
      return t;
    }).toList();
    state = state.copyWith(overlayTracks: next);
  }

  void toggleTrackLocked(String trackId) {
    final next = state.overlayTracks.map((t) {
      if (t.id == trackId) return t.copyWith(locked: !t.locked);
      return t;
    }).toList();
    state = state.copyWith(overlayTracks: next);
  }

  // === SELECTION ACTIONS ===
  void selectClip(String? clipId) {
    if (state.selectedClipId == clipId) return;
    state = state.copyWith(selectedClipId: clipId, clearSelectedClip: clipId == null);
  }

  void selectTrack(String? trackId) {
    state = state.copyWith(selectedTrackId: trackId);
  }

  void deleteSelectedItem() {
    final selId = state.selectedClipId;
    if (selId == null) return;

    if (state.overlayClips.any((c) => c.id == selId)) {
      removeOverlayClip(selId);
      return;
    }
    if (state.audioClips.any((c) => c.id == selId)) {
      removeAudioClip(selId);
      return;
    }
    if (state.subtitles.any((s) => s.id == selId)) {
      removeSubtitleClip(selId);
      return;
    }
    if (state.cutSegments.any((s) => s.id == selId)) {
      removeCutSegment(selId);
      return;
    }
    if (state.splitSegments.any((s) => s.id == selId)) {
      removeSplitSegment(selId);
      return;
    }
    if (state.mergePlaylist.any((m) => m.id == selId)) {
      removeMergeItem(selId);
      return;
    }
  }

  // === OVERLAY CLIP ACTIONS ===
  void addOverlayClip(OverlayClip clip) {
    var effectiveClip = clip;
    var tracks = state.overlayTracks;

    // Safety fallback: if clip.trackId does not match any track in overlayTracks
    if (!tracks.any((t) => t.id == effectiveClip.trackId)) {
      if (state.selectedTrackId != null && tracks.any((t) => t.id == state.selectedTrackId)) {
        effectiveClip = effectiveClip.copyWith(trackId: state.selectedTrackId!);
      } else if (tracks.isNotEmpty) {
        effectiveClip = effectiveClip.copyWith(trackId: tracks.first.id);
      } else {
        final newTrack = OverlayTrack(
          id: 'track-ov-${DateTime.now().millisecondsSinceEpoch}',
          name: 'Lớp phủ 1',
        );
        tracks = [newTrack];
        effectiveClip = effectiveClip.copyWith(trackId: newTrack.id);
      }
    }

    final next = [...state.overlayClips, effectiveClip];
    recordAction(
      'Chèn ảnh lớp phủ: ${effectiveClip.name}',
      state.copyWith(
        overlayTracks: tracks,
        overlayClips: next,
        selectedClipId: effectiveClip.id,
        selectedTrackId: effectiveClip.trackId,
      ),
    );
  }

  void removeOverlayClip(String id) {
    final next = state.overlayClips.where((c) => c.id != id).toList();
    final clearSel = state.selectedClipId == id;
    recordAction('Xoá ảnh lớp phủ', state.copyWith(overlayClips: next, clearSelectedClip: clearSel));
  }

  void moveOverlayClip(String id, double newStart, double maxDuration) {
    final idx = state.overlayClips.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final clip = state.overlayClips[idx];
    final length = clip.end - clip.start;
    final clampedStart = newStart.clamp(0.0, (maxDuration - length).clamp(0.0, maxDuration));
    final clampedEnd = (clampedStart + length).clamp(0.0, maxDuration);

    final updated = clip.copyWith(start: clampedStart, end: clampedEnd);
    final nextList = List<OverlayClip>.from(state.overlayClips);
    nextList[idx] = updated;
    state = state.copyWith(overlayClips: nextList);
  }

  void resizeOverlayClip(String id, double newEnd, double maxDuration) {
    final idx = state.overlayClips.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final clip = state.overlayClips[idx];
    final clampedEnd = newEnd.clamp(clip.start + 0.2, maxDuration);

    final updated = clip.copyWith(end: clampedEnd);
    final nextList = List<OverlayClip>.from(state.overlayClips);
    nextList[idx] = updated;
    state = state.copyWith(overlayClips: nextList);
  }

  void updateOverlayClipGeometry(String id, {double? x, double? y, double? width, double? height, double? opacity, double? borderRadius}) {
    final idx = state.overlayClips.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final clip = state.overlayClips[idx];
    final updated = clip.copyWith(
      x: x?.clamp(0.0, 95.0),
      y: y?.clamp(0.0, 95.0),
      width: width?.clamp(5.0, 100.0),
      height: height?.clamp(5.0, 100.0),
      opacity: opacity?.clamp(0.1, 1.0),
      borderRadius: borderRadius,
    );
    final nextList = List<OverlayClip>.from(state.overlayClips);
    nextList[idx] = updated;
    state = state.copyWith(overlayClips: nextList);
  }

  void resizeOverlayClipStart(String id, double newStart, double maxDuration) {
    final idx = state.overlayClips.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final clip = state.overlayClips[idx];
    final clampedStart = newStart.clamp(0.0, clip.end - 0.2);
    final updated = clip.copyWith(start: clampedStart);
    final nextList = List<OverlayClip>.from(state.overlayClips);
    nextList[idx] = updated;
    state = state.copyWith(overlayClips: nextList);
  }

  // === AUDIO TRACK ACTIONS ===
  void addAudioTrack() {
    final nextIdx = state.audioTracks.length + 1;
    final track = StudioAudioTrack(
      id: 'track-au-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Âm thanh $nextIdx',
    );
    final next = [...state.audioTracks, track];
    recordAction('Thêm làn âm thanh mới', state.copyWith(audioTracks: next, selectedTrackId: track.id));
  }

  void removeAudioTrack(String trackId) {
    final nextTracks = state.audioTracks.where((t) => t.id != trackId).toList();
    final nextClips = state.audioClips.where((c) => c.trackId != trackId).toList();
    final clearSelTrack = state.selectedTrackId == trackId;
    recordAction(
      'Xoá làn âm thanh',
      state.copyWith(
        audioTracks: nextTracks,
        audioClips: nextClips,
        clearSelectedTrack: clearSelTrack,
      ),
    );
  }

  void toggleAudioTrackMute(String trackId) {
    final next = state.audioTracks.map((t) {
      if (t.id == trackId) return t.copyWith(muted: !t.muted);
      return t;
    }).toList();
    state = state.copyWith(audioTracks: next);
  }

  void setAudioTrackVolume(String trackId, int volume) {
    final next = state.audioTracks.map((t) {
      if (t.id == trackId) return t.copyWith(volume: volume.clamp(0, 200));
      return t;
    }).toList();
    state = state.copyWith(audioTracks: next);
  }

  // === AUDIO CLIP ACTIONS ===
  void addAudioClip(AudioClip clip) {
    var effectiveClip = clip;
    var tracks = state.audioTracks;

    // Safety fallback: if clip.trackId does not match any track in audioTracks
    if (!tracks.any((t) => t.id == effectiveClip.trackId)) {
      if (state.selectedTrackId != null && tracks.any((t) => t.id == state.selectedTrackId)) {
        effectiveClip = effectiveClip.copyWith(trackId: state.selectedTrackId!);
      } else if (tracks.isNotEmpty) {
        effectiveClip = effectiveClip.copyWith(trackId: tracks.first.id);
      } else {
        final newTrack = StudioAudioTrack(
          id: 'track-au-${DateTime.now().millisecondsSinceEpoch}',
          name: 'Âm thanh 1',
        );
        tracks = [newTrack];
        effectiveClip = effectiveClip.copyWith(trackId: newTrack.id);
      }
    }

    final next = [...state.audioClips, effectiveClip];
    recordAction(
      'Thêm âm thanh: ${effectiveClip.name}',
      state.copyWith(
        audioTracks: tracks,
        audioClips: next,
        selectedClipId: effectiveClip.id,
        selectedTrackId: effectiveClip.trackId,
      ),
    );
  }

  void removeAudioClip(String id) {
    final next = state.audioClips.where((a) => a.id != id).toList();
    final clearSel = state.selectedClipId == id;
    recordAction('Xoá clip âm thanh', state.copyWith(audioClips: next, clearSelectedClip: clearSel));
  }

  void updateAudioClip(AudioClip clip) {
    final idx = state.audioClips.indexWhere((a) => a.id == clip.id);
    if (idx == -1) return;
    final nextList = List<AudioClip>.from(state.audioClips);
    nextList[idx] = clip;
    state = state.copyWith(audioClips: nextList);
  }

  void setAudioClipVolume(String id, int volume) {
    final idx = state.audioClips.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final clip = state.audioClips[idx];
    final updated = clip.copyWith(volume: volume.clamp(0, 200));
    final nextList = List<AudioClip>.from(state.audioClips);
    nextList[idx] = updated;
    state = state.copyWith(audioClips: nextList);
  }

  void toggleAudioClipMute(String id) {
    final idx = state.audioClips.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final clip = state.audioClips[idx];
    final updated = clip.copyWith(muted: !clip.muted);
    final nextList = List<AudioClip>.from(state.audioClips);
    nextList[idx] = updated;
    state = state.copyWith(audioClips: nextList);
  }

  void moveAudioClip(String id, double newStart, double maxDuration) {
    final idx = state.audioClips.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final clip = state.audioClips[idx];
    final length = clip.end - clip.start;
    final clampedStart = newStart.clamp(0.0, (maxDuration - length).clamp(0.0, maxDuration));
    final clampedEnd = (clampedStart + length).clamp(0.0, maxDuration);

    final updated = clip.copyWith(start: clampedStart, end: clampedEnd);
    final nextList = List<AudioClip>.from(state.audioClips);
    nextList[idx] = updated;
    state = state.copyWith(audioClips: nextList);
  }

  void resizeAudioClip(String id, double newEnd, double maxDuration) {
    final idx = state.audioClips.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final clip = state.audioClips[idx];
    final clampedEnd = newEnd.clamp(clip.start + 0.2, maxDuration);

    final updated = clip.copyWith(end: clampedEnd);
    final nextList = List<AudioClip>.from(state.audioClips);
    nextList[idx] = updated;
    state = state.copyWith(audioClips: nextList);
  }

  void resizeAudioClipStart(String id, double newStart, double maxDuration) {
    final idx = state.audioClips.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    final clip = state.audioClips[idx];
    final clampedStart = newStart.clamp(0.0, clip.end - 0.2);

    final updated = clip.copyWith(start: clampedStart);
    final nextList = List<AudioClip>.from(state.audioClips);
    nextList[idx] = updated;
    state = state.copyWith(audioClips: nextList);
  }

  // === SUBTITLE ACTIONS ===
  void addSubtitleClip(SubtitleClip clip) {
    final next = [...state.subtitles, clip];
    recordAction('Thêm phụ đề', state.copyWith(subtitles: next, selectedClipId: clip.id));
  }

  void removeSubtitleClip(String id) {
    final next = state.subtitles.where((s) => s.id != id).toList();
    final clearSel = state.selectedClipId == id;
    recordAction('Xoá phụ đề', state.copyWith(subtitles: next, clearSelectedClip: clearSel));
  }

  void moveSubtitleClip(String id, double newStart, double maxDuration) {
    final idx = state.subtitles.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final clip = state.subtitles[idx];
    final length = clip.end - clip.start;
    final clampedStart = newStart.clamp(0.0, (maxDuration - length).clamp(0.0, maxDuration));
    final clampedEnd = (clampedStart + length).clamp(0.0, maxDuration);

    final updated = clip.copyWith(start: clampedStart, end: clampedEnd);
    final nextList = List<SubtitleClip>.from(state.subtitles);
    nextList[idx] = updated;
    state = state.copyWith(subtitles: nextList);
  }

  void resizeSubtitleClip(String id, double newEnd, double maxDuration) {
    final idx = state.subtitles.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final clip = state.subtitles[idx];
    final clampedEnd = newEnd.clamp(clip.start + 0.2, maxDuration);

    final updated = clip.copyWith(end: clampedEnd);
    final nextList = List<SubtitleClip>.from(state.subtitles);
    nextList[idx] = updated;
    state = state.copyWith(subtitles: nextList);
  }

  void resizeSubtitleClipStart(String id, double newStart, double maxDuration) {
    final idx = state.subtitles.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final clip = state.subtitles[idx];
    final clampedStart = newStart.clamp(0.0, clip.end - 0.2);

    final updated = clip.copyWith(start: clampedStart);
    final nextList = List<SubtitleClip>.from(state.subtitles);
    nextList[idx] = updated;
    state = state.copyWith(subtitles: nextList);
  }

  void updateSubtitleText(String id, {String? textTrans, String? textOrig, String? text, String? textVi, String? textSecondary}) {
    final idx = state.subtitles.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final clip = state.subtitles[idx];
    final updated = clip.copyWith(
      text: text ?? textOrig ?? clip.text,
      textVi: textVi ?? textTrans ?? clip.textVi,
      textSecondary: textSecondary ?? clip.textSecondary,
    );
    final nextList = List<SubtitleClip>.from(state.subtitles);
    nextList[idx] = updated;
    state = state.copyWith(subtitles: nextList);
  }

  void updateSubtitleClip(SubtitleClip clip) {
    final idx = state.subtitles.indexWhere((s) => s.id == clip.id);
    if (idx == -1) return;
    final nextList = List<SubtitleClip>.from(state.subtitles);
    nextList[idx] = clip;
    state = state.copyWith(subtitles: nextList);
  }

  void setSubtitles(List<SubtitleClip> newSubs, {bool recordUndo = true}) {
    if (recordUndo) {
      recordAction('Cập nhật phụ đề', state.copyWith(subtitles: newSubs));
    } else {
      state = state.copyWith(subtitles: newSubs);
    }
  }

  bool loadSubtitlesFromPipeline(String projectDir, String videoStem) {
    // 1. Check exact job folder
    final possibleDirs = [
      p.join(projectDir, 'workspace', 'job_$videoStem'),
      p.join(projectDir, 'workspace', videoStem),
    ];

    // Also search in workspace/ for matching job directory
    final wsDir = Directory(p.join(projectDir, 'workspace'));
    if (wsDir.existsSync()) {
      try {
        final entries = wsDir.listSync();
        for (final entry in entries) {
          if (entry is Directory && entry.path.contains(videoStem)) {
            possibleDirs.add(entry.path);
          }
        }
      } catch (_) {}
    }

    File? foundFile;
    for (final dirPath in possibleDirs) {
      for (final filename in ['s08c_timing.json', 's08_translation.json', 's07_transcript.json']) {
        final f = File(p.join(dirPath, filename));
        if (f.existsSync() && f.lengthSync() > 10) {
          foundFile = f;
          break;
        }
      }
      if (foundFile != null) break;
    }

    if (foundFile == null) return false;

    try {
      final content = foundFile.readAsStringSync();
      final List<dynamic> jsonList = jsonDecode(content);
      final loaded = <SubtitleClip>[];
      for (int i = 0; i < jsonList.length; i++) {
        final item = jsonList[i];
        if (item is Map<String, dynamic>) {
          loaded.add(SubtitleClip.fromJson(item));
        }
      }
      if (loaded.isNotEmpty) {
        recordAction('Nạp ${loaded.length} phụ đề từ Pipeline', state.copyWith(subtitles: loaded));
        return true;
      }
    } catch (_) {}

    return false;
  }

  void updateInpaintConfig({
    bool? enabled,
    List<double>? region,
    String? mode,
    String? color,
    double? opacity,
    String? engine,
    int? blurRadius,
    String? method,
    String? borderColor,
    int? borderWidth,
    int? borderRadius,
    double? paddingY,
    double? boxLeadIn,
    double? boxLeadOut,
    bool? watermarkEnabled,
    String? watermarkImagePath,
    List<double>? watermarkRegion,
    double? watermarkOpacity,
    StudioInpaintConfig? config,
  }) {
    if (config != null) {
      state = state.copyWith(inpaintConfig: config);
    } else {
      state = state.copyWith(
        inpaintConfig: state.inpaintConfig.copyWith(
          enabled: enabled,
          region: region,
          mode: mode,
          color: color,
          opacity: opacity,
          engine: engine,
          blurRadius: blurRadius,
          method: method,
          borderColor: borderColor,
          borderWidth: borderWidth,
          borderRadius: borderRadius,
          paddingY: paddingY,
          boxLeadIn: boxLeadIn,
          boxLeadOut: boxLeadOut,
          watermarkEnabled: watermarkEnabled,
          watermarkImagePath: watermarkImagePath,
          watermarkRegion: watermarkRegion,
          watermarkOpacity: watermarkOpacity,
        ),
      );
    }
  }

  void alignSubtitle(String alignment) {
    double targetY = 85.0;
    if (alignment == 'top') {
      targetY = 12.0;
    } else if (alignment == 'center') {
      targetY = 48.0;
    }
    updateSubStyle(state.subStyle.copyWith(
      alignment: alignment,
      posX: 50.0,
      posY: targetY,
    ));
  }

  void updateSubStyle(SubStyle style) {
    state = state.copyWith(subStyle: style);
  }

  void commitSubStyleAction(SubStyle style) {
    recordAction('Cập nhật kiểu dáng phụ đề', state.copyWith(subStyle: style));
  }

  void updateMixState(AudioMixState mix) {
    state = state.copyWith(mixState: mix);
  }

  void toggleMuteVideo() {
    final next = !state.mixState.origMuted;
    recordAction(
      next ? 'Tắt tiếng Video gốc' : 'Bật tiếng Video gốc',
      state.copyWith(mixState: state.mixState.copyWith(origMuted: next)),
    );
  }

  void toggleMuteMusic() {
    final next = !state.mixState.musicMuted;
    recordAction(
      next ? 'Tắt tiếng Nhạc nền' : 'Bật tiếng Nhạc nền',
      state.copyWith(mixState: state.mixState.copyWith(musicMuted: next)),
    );
  }

  void toggleMuteSfx() {
    final next = !state.mixState.sfxMuted;
    recordAction(
      next ? 'Tắt tiếng Hiệu ứng' : 'Bật tiếng Hiệu ứng',
      state.copyWith(mixState: state.mixState.copyWith(sfxMuted: next)),
    );
  }

  void updateSubtitleRegion(List<double>? region) {
    if (region == null) {
      updateSubStyle(state.subStyle.copyWith(setSubtitleRegionNull: true));
    } else {
      final clamped = [
        double.parse(region[0].clamp(0.0, 0.95).toStringAsFixed(3)),
        double.parse(region[1].clamp(0.0, 0.95).toStringAsFixed(3)),
        double.parse(region[2].clamp(region[0] + 0.02, 1.0).toStringAsFixed(3)),
        double.parse(region[3].clamp(region[1] + 0.02, 1.0).toStringAsFixed(3)),
      ];
      final wPct = (clamped[3] - clamped[1]) * 100.0;
      final xCenter = (clamped[1] + (clamped[3] - clamped[1]) / 2) * 100.0;
      final yTop = clamped[0] * 100.0;
      updateSubStyle(state.subStyle.copyWith(
        subtitleRegion: clamped,
        posX: double.parse(xCenter.toStringAsFixed(1)),
        posY: double.parse(yTop.toStringAsFixed(1)),
        boxWidthPct: double.parse(wPct.toStringAsFixed(1)),
      ));
    }
  }

  void updateSubtitleSecondaryRegion(List<double>? region) {
    if (region == null) {
      updateSubStyle(state.subStyle.copyWith(setSubtitleSecondaryRegionNull: true));
    } else {
      final clamped = [
        double.parse(region[0].clamp(0.0, 0.95).toStringAsFixed(3)),
        double.parse(region[1].clamp(0.0, 0.95).toStringAsFixed(3)),
        double.parse(region[2].clamp(region[0] + 0.02, 1.0).toStringAsFixed(3)),
        double.parse(region[3].clamp(region[1] + 0.02, 1.0).toStringAsFixed(3)),
      ];
      final wPct = (clamped[3] - clamped[1]) * 100.0;
      final xCenter = (clamped[1] + (clamped[3] - clamped[1]) / 2) * 100.0;
      final yTop = clamped[0] * 100.0;
      updateSubStyle(state.subStyle.copyWith(
        subtitleSecondaryRegion: clamped,
        secPosX: double.parse(xCenter.toStringAsFixed(1)),
        secPosY: double.parse(yTop.toStringAsFixed(1)),
        secBoxWidthPct: double.parse(wPct.toStringAsFixed(1)),
      ));
    }
  }

  void updateInpaintRegion(List<double> region) {
    final clamped = [
      double.parse(region[0].clamp(0.0, 0.98).toStringAsFixed(3)),
      double.parse(region[1].clamp(0.0, 0.98).toStringAsFixed(3)),
      double.parse(region[2].clamp(region[0] + 0.01, 1.0).toStringAsFixed(3)),
      double.parse(region[3].clamp(region[1] + 0.01, 1.0).toStringAsFixed(3)),
    ];
    updateInpaintConfig(region: clamped);
  }

  void updateWatermarkRegion(List<double> region) {
    final clamped = [
      double.parse(region[0].clamp(0.0, 0.98).toStringAsFixed(3)),
      double.parse(region[1].clamp(0.0, 0.98).toStringAsFixed(3)),
      double.parse(region[2].clamp(region[0] + 0.01, 1.0).toStringAsFixed(3)),
      double.parse(region[3].clamp(region[1] + 0.01, 1.0).toStringAsFixed(3)),
    ];
    updateInpaintConfig(watermarkRegion: clamped);
  }

  void setVideoSpeed(double speed) {
    if ((state.videoSpeed - speed).abs() < 0.01) return;
    recordAction(
      'Đổi tốc độ video gốc: ${speed}x',
      state.copyWith(videoSpeed: speed),
    );
  }
}

enum StudioGizmoLayer {
  none,
  inpaint,
  primarySub,
  secondarySub,
  watermark,
}

final activeStudioGizmoLayerProvider =
    StateProvider<StudioGizmoLayer>((ref) => StudioGizmoLayer.none);

final studioStateProvider =
    StateNotifierProvider.autoDispose<StudioStateNotifier, StudioSnapshot>((ref) {
  return StudioStateNotifier();
});

final studioToolModeProvider =
    StateProvider<StudioToolMode>((ref) => StudioToolMode.cut);
