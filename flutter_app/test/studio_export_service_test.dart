import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_video_desktop/core/studio_export_service.dart';
import 'package:sub_video_desktop/core/engine_resolver.dart';
import 'package:sub_video_desktop/models/studio_state.dart';

void main() {
  group('StudioExportService Tests', () {
    test('ensureDirectories creates cut, merge, and output folders', () async {
      final tempDir = Directory.systemTemp.createTempSync('studio_export_test_');
      try {
        final dirs = await StudioExportService.ensureDirectories(tempDir.path);
        expect(dirs.containsKey('cut'), true);
        expect(dirs.containsKey('merge'), true);
        expect(dirs.containsKey('output'), true);

        expect(await Directory(p.join(tempDir.path, 'cut')).exists(), true);
        expect(await Directory(p.join(tempDir.path, 'merge')).exists(), true);
        expect(await Directory(p.join(tempDir.path, 'output')).exists(), true);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('EngineResolver.resolveScript resolves composite_render script correctly', () {
      final script = EngineResolver.resolveScript('composite_render.py');
      expect(script, isNotNull);
      expect(script!.existsSync(), true);
      expect(script.path.endsWith('composite_render.py') || script.path.endsWith('composite_render.pyc'), true);
    });

    test('AudioClip.fromJson normalizes legacy 60 and 80 volume to 100', () {
      final clip60 = AudioClip.fromJson({
        'id': 'c1',
        'trackId': 'sfx',
        'name': 'sfx.wav',
        'fullPath': '/path/to/sfx.wav',
        'start': 0.0,
        'end': 5.0,
        'volume': 60,
        'muted': false,
      });
      expect(clip60.volume, 100);

      final clip80 = AudioClip.fromJson({
        'id': 'c2',
        'trackId': 'music',
        'name': 'music.mp3',
        'fullPath': '/path/to/music.mp3',
        'start': 0.0,
        'end': 30.0,
        'volume': 80,
        'muted': false,
      });
      expect(clip80.volume, 100);

      final clip150 = AudioClip.fromJson({
        'id': 'c3',
        'trackId': 'sfx',
        'name': 'custom.wav',
        'fullPath': '/path/to/custom.wav',
        'start': 0.0,
        'end': 10.0,
        'volume': 150,
        'muted': false,
      });
      expect(clip150.volume, 150);
    });

    test('SubStyle serialization roundtrip preserves padding, gap, and split boxes', () {
      const style = SubStyle(
        fontFamily: 'Montserrat',
        fontSize: 26,
        secondaryFontSize: 20,
        fontColor: '#4ADE80',
        origColor: '#FFFFFF',
        boxBgColor: '#1E293B',
        boxOpacity: 0.85,
        boxBorderRadius: 12.0,
        boxPaddingX: 18.0,
        boxPaddingY: 10.0,
        boxGap: 14.0,
        boxSplit: true,
        separateSecPos: true,
        secPosX: 45.0,
        secPosY: 20.0,
        secBoxWidthPct: 80.0,
        subtitleRegion: [0.76, 0.05, 0.86, 0.95],
        subtitleSecondaryRegion: [0.87, 0.05, 0.95, 0.95],
      );

      final json = style.toJson();
      expect(json['fontSize'], 26);
      expect(json['secondaryFontSize'], 20);
      expect(json['boxPaddingX'], 18.0);
      expect(json['boxGap'], 14.0);
      expect(json['boxSplit'], true);
      expect(json['separateSecPos'], true);
      expect(json['subtitleRegion'], [0.76, 0.05, 0.86, 0.95]);
      expect(json['subtitleSecondaryRegion'], [0.87, 0.05, 0.95, 0.95]);

      final restored = SubStyle.fromJson(json);
      expect(restored.fontFamily, 'Montserrat');
      expect(restored.fontSize, 26);
      expect(restored.secondaryFontSize, 20);
      expect(restored.boxPaddingX, 18.0);
      expect(restored.boxGap, 14.0);
      expect(restored.boxSplit, true);
      expect(restored.separateSecPos, true);
      expect(restored.secPosX, 45.0);
      expect(restored.subtitleRegion, [0.76, 0.05, 0.86, 0.95]);
      expect(restored.effectiveSubtitleRegion, [0.76, 0.05, 0.86, 0.95]);
      expect(restored.effectiveSubtitleSecondaryRegion, [0.87, 0.05, 0.95, 0.95]);
    });

    test('StudioInpaintConfig serialization and copyWith works correctly', () {
      const inpaint = StudioInpaintConfig(
        enabled: true,
        region: [0.80, 0.05, 0.95, 0.95],
        mode: 'box_color',
        color: '#000000',
        opacity: 0.8,
        engine: 'ffmpeg_blur',
        blurRadius: 20,
        method: 'vertical_gradient',
        borderColor: '#facc15',
        borderWidth: 2,
        borderRadius: 8,
        paddingY: 0.03,
        watermarkEnabled: true,
        watermarkImagePath: '/path/to/logo.png',
        watermarkRegion: [0.03, 0.82, 0.06, 0.96],
        watermarkOpacity: 0.85,
      );

      final json = inpaint.toJson();
      expect(json['enabled'], true);
      expect(json['region'], [0.80, 0.05, 0.95, 0.95]);
      expect(json['engine'], 'ffmpeg_blur');
      expect(json['blur_radius'], 20);
      expect(json['watermark_enabled'], true);
      expect(json['watermark_image_path'], '/path/to/logo.png');
      expect(json['watermark_region'], [0.03, 0.82, 0.06, 0.96]);

      final restored = StudioInpaintConfig.fromJson(json);
      expect(restored.enabled, true);
      expect(restored.region.length, 4);
      expect(restored.opacity, 0.8);
      expect(restored.engine, 'ffmpeg_blur');
      expect(restored.blurRadius, 20);
      expect(restored.watermarkEnabled, true);
      expect(restored.watermarkImagePath, '/path/to/logo.png');

      final modified = restored.copyWith(mode: 'blur', opacity: 0.9, blurRadius: 30);
      expect(modified.mode, 'blur');
      expect(modified.opacity, 0.9);
      expect(modified.blurRadius, 30);
      expect(modified.enabled, true);
    });

    test('SubtitleClip dual-mapping supports both video editor and studio draft formats', () {
      // Format 1: Video Editor format (text, text_vi)
      final clip1 = SubtitleClip.fromJson({
        'id': 'sub_1',
        'start': 1.0,
        'end': 4.5,
        'text': 'Hello world',
        'text_vi': 'Xin chào thế giới',
        'speaker': 'Nam',
        'gender': 'male',
      });
      expect(clip1.text, 'Hello world');
      expect(clip1.textVi, 'Xin chào thế giới');
      expect(clip1.textOrig, 'Hello world');
      expect(clip1.textTrans, 'Xin chào thế giới');
      expect(clip1.speaker, 'Nam');
      expect(clip1.gender, 'male');

      // Format 2: Studio Draft legacy format (textOrig, textTrans)
      final clip2 = SubtitleClip.fromJson({
        'id': 'sub_2',
        'start': 5.0,
        'end': 8.0,
        'textOrig': 'Good morning',
        'textTrans': 'Chào buổi sáng',
        'speaker': 'Nữ',
        'gender': 'female',
      });
      expect(clip2.text, 'Good morning');
      expect(clip2.textVi, 'Chào buổi sáng');
      expect(clip2.textOrig, 'Good morning');
      expect(clip2.textTrans, 'Chào buổi sáng');
      expect(clip2.speaker, 'Nữ');
      expect(clip2.gender, 'female');

      // Serialized JSON contains all fields for backward & forward compatibility
      final json2 = clip2.toJson();
      expect(json2['text'], 'Good morning');
      expect(json2['text_vi'], 'Chào buổi sáng');
      expect(json2['textOrig'], 'Good morning');
      expect(json2['textTrans'], 'Chào buổi sáng');
      expect(json2['speaker'], 'Nữ');
      expect(json2['gender'], 'female');
    });

    test('SubStyle roundtrip serialization preserves secondaryFontFamily and SubBox settings', () {
      const original = SubStyle(
        fontFamily: 'Montserrat',
        secondaryFontFamily: 'Roboto',
        fontSize: 26,
        secondaryFontSize: 18,
        fontColor: '#FFFFFF',
        origColor: '#D0D0D0',
        showMainSub: true,
        showSubSub: true,
        showSubBox: true,
        boxBgColor: '#0F172A',
        boxOpacity: 0.85,
        boxBorderRadius: 8.0,
        boxBorderColor: '#40FFFFFF',
        boxBorderWidth: 2.0,
        boxGap: 12.0,
        boxSplit: true,
      );

      final json = original.toJson();
      expect(json['fontFamily'], 'Montserrat');
      expect(json['secondaryFontFamily'], 'Roboto');
      expect(json['fontSize'], 26);
      expect(json['boxBgColor'], '#0F172A');
      expect(json['boxOpacity'], 0.85);
      expect(json['boxBorderWidth'], 2.0);
      expect(json['boxSplit'], true);

      final recovered = SubStyle.fromJson(json);
      expect(recovered.fontFamily, 'Montserrat');
      expect(recovered.secondaryFontFamily, 'Roboto');
      expect(recovered.fontSize, 26);
      expect(recovered.secondaryFontSize, 18);
      expect(recovered.boxBgColor, '#0F172A');
      expect(recovered.boxOpacity, 0.85);
      expect(recovered.boxBorderWidth, 2.0);
      expect(recovered.boxSplit, true);
    });

    test('StudioInpaintConfig roundtrip preserves box lead-in/out and watermark settings', () {
      const config = StudioInpaintConfig(
        enabled: true,
        region: [0.70, 0.10, 0.90, 0.90],
        engine: 'ffmpeg_blur',
        blurRadius: 20,
        boxLeadIn: 0.35,
        boxLeadOut: 0.20,
        watermarkEnabled: true,
        watermarkImagePath: '/path/to/logo.png',
        watermarkOpacity: 0.8,
      );

      final json = config.toJson();
      expect(json['enabled'], true);
      expect(json['box_lead_in'], 0.35);
      expect(json['box_lead_out'], 0.20);
      expect(json['watermark_enabled'], true);
      expect(json['watermark_image_path'], '/path/to/logo.png');

      final recovered = StudioInpaintConfig.fromJson(json);
      expect(recovered.enabled, true);
      expect(recovered.boxLeadIn, 0.35);
      expect(recovered.boxLeadOut, 0.20);
      expect(recovered.watermarkEnabled, true);
      expect(recovered.watermarkImagePath, '/path/to/logo.png');
      expect(recovered.watermarkOpacity, 0.8);
    });

    test('StudioAudioTrack serialization roundtrip preserves track settings', () {
      const track = StudioAudioTrack(
        id: 'track-au-custom',
        name: 'Nhạc nền chính',
        muted: true,
        volume: 120,
      );
      final json = track.toJson();
      expect(json['id'], 'track-au-custom');
      expect(json['name'], 'Nhạc nền chính');
      expect(json['muted'], true);
      expect(json['volume'], 120);

      final restored = StudioAudioTrack.fromJson(json);
      expect(restored.id, 'track-au-custom');
      expect(restored.name, 'Nhạc nền chính');
      expect(restored.muted, true);
      expect(restored.volume, 120);
    });

    test('StudioSnapshot auto-migrates legacy audio draft with music and sfx clips', () {
      final legacyDraft = {
        'id': 'snap_legacy_1',
        'label': 'Legacy Project',
        'time': '10:00:00',
        'audioClips': [
          {
            'id': 'c1',
            'trackId': 'music',
            'name': 'bgm.mp3',
            'fullPath': '/path/to/bgm.mp3',
            'start': 0.0,
            'end': 30.0,
            'volume': 80,
          },
          {
            'id': 'c2',
            'trackId': 'sfx',
            'name': 'whoosh.wav',
            'fullPath': '/path/to/whoosh.wav',
            'start': 5.0,
            'end': 7.0,
            'volume': 60,
          },
        ],
      };

      final snapshot = StudioSnapshot.fromJson(legacyDraft);
      // Confirms both tracks are dynamically present
      expect(snapshot.audioTracks.length, 2);
      expect(snapshot.audioTracks[0].id, 'track-au-1');
      expect(snapshot.audioTracks[1].id, 'track-au-2');

      // Confirms clips were normalized
      expect(snapshot.audioClips[0].trackId, 'track-au-1');
      expect(snapshot.audioClips[1].trackId, 'track-au-2');
    });
  });
}

