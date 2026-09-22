import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/studio_state.dart';
import 'package:sub_video_desktop/core/studio_state_notifier.dart';

void main() {
  group('OverlayClip Inpaint Model Tests', () {
    test('Khởi tạo OverlayClip dạng inpaint với các giá trị mặc định chuẩn', () {
      const clip = OverlayClip(
        id: 'inpaint-test-1',
        trackId: 'track-ov-1',
        name: 'Vùng che mờ 1',
        overlayType: 'inpaint',
        start: 1.0,
        end: 5.0,
        x: 10.0,
        y: 20.0,
        width: 30.0,
        height: 15.0,
      );

      expect(clip.isInpaint, isTrue);
      expect(clip.name, 'Vùng che mờ 1');
      expect(clip.overlayType, 'inpaint');
      expect(clip.inpaintEngine, 'ffmpeg_blur');
      expect(clip.blurRadius, 15);
      expect(clip.boxColor, '#000000');
      expect(clip.boxOpacity, 0.8);
      expect(clip.borderColor, '#EF4444');
      expect(clip.borderWidth, 0);
    });

    test('toJson và fromJson bảo toàn toàn bộ cấu hình inpaint', () {
      const original = OverlayClip(
        id: 'inpaint-2',
        trackId: 'track-ov-2',
        name: 'Hộp màu đen',
        overlayType: 'inpaint',
        start: 2.5,
        end: 8.0,
        x: 15.0,
        y: 25.0,
        width: 40.0,
        height: 20.0,
        inpaintEngine: 'box_color',
        blurRadius: 25,
        boxColor: '#1E293B',
        boxOpacity: 0.95,
        borderColor: '#3B82F6',
        borderWidth: 2,
        method: 'telea',
      );

      final json = original.toJson();
      final restored = OverlayClip.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.trackId, original.trackId);
      expect(restored.isInpaint, isTrue);
      expect(restored.overlayType, 'inpaint');
      expect(restored.inpaintEngine, 'box_color');
      expect(restored.blurRadius, 25);
      expect(restored.boxColor, '#1E293B');
      expect(restored.boxOpacity, 0.95);
      expect(restored.borderColor, '#3B82F6');
      expect(restored.borderWidth, 2);
      expect(restored.method, 'telea');
    });

    test('Tương thích ngược 100% với JSON draft cũ không có các trường inpaint', () {
      final legacyJson = {
        'id': 'legacy-img-1',
        'trackId': 'track-ov-1',
        'name': 'Logo kênh',
        'imagePath': '/path/to/logo.png',
        'start': 0.0,
        'end': 10.0,
        'x': 5.0,
        'y': 5.0,
        'width': 20.0,
        'height': 20.0,
        'opacity': 1.0,
      };

      final clip = OverlayClip.fromJson(legacyJson);
      expect(clip.isInpaint, isFalse);
      expect(clip.overlayType, 'image');
      expect(clip.imagePath, '/path/to/logo.png');
      expect(clip.inpaintEngine, 'ffmpeg_blur');
      expect(clip.blurRadius, 15);
      expect(clip.boxColor, '#000000');
    });
  });

  group('StudioStateNotifier Inpaint Management Tests', () {
    test('addInpaintClip tự động gán vào track hợp lệ, kích thước mặc định và hỗ trợ Undo', () {
      final notifier = StudioStateNotifier();

      // Mặc định ban đầu chưa có overlay clip
      expect(notifier.state.overlayClips, isEmpty);

      // Thêm inpaint clip
      notifier.addInpaintClip(
        trackId: 'track-ov-1',
        start: 2.0,
        end: 7.0,
        inpaintEngine: 'box_color',
      );

      expect(notifier.state.overlayClips.length, 1);
      final clip = notifier.state.overlayClips.first;
      expect(clip.isInpaint, isTrue);
      expect(clip.trackId, 'track-ov-1');
      expect(clip.start, 2.0);
      expect(clip.end, 7.0);
      expect(clip.inpaintEngine, 'box_color');
      expect(notifier.state.selectedClipId, clip.id);

      // Kiểm tra Undo hoàn tác lại
      expect(notifier.canUndo, isTrue);
      notifier.undo();
      expect(notifier.state.overlayClips, isEmpty);

      // Kiểm tra Redo phục hồi
      expect(notifier.canRedo, isTrue);
      notifier.redo();
      expect(notifier.state.overlayClips.length, 1);
      expect(notifier.state.overlayClips.first.id, clip.id);
    });

    test('updateOverlayClipProperties cập nhật thông số inpaint chính xác', () {
      final notifier = StudioStateNotifier();
      notifier.addInpaintClip(start: 0.0, end: 5.0);
      final clipId = notifier.state.overlayClips.first.id;

      notifier.updateOverlayClipProperties(
        clipId,
        inpaintEngine: 'apple_vision_inpaint',
        blurRadius: 30,
        boxColor: '#FF0000',
        boxOpacity: 0.5,
      );

      final updated = notifier.state.overlayClips.firstWhere((c) => c.id == clipId);
      expect(updated.inpaintEngine, 'apple_vision_inpaint');
      expect(updated.blurRadius, 30);
      expect(updated.boxColor, '#FF0000');
      expect(updated.boxOpacity, 0.5);
    });

    test('removeOverlayClip xóa clip inpaint thành công và cho phép undo', () {
      final notifier = StudioStateNotifier();
      notifier.addInpaintClip(start: 1.0, end: 3.0);
      final clipId = notifier.state.overlayClips.first.id;

      notifier.removeOverlayClip(clipId);
      expect(notifier.state.overlayClips, isEmpty);

      notifier.undo();
      expect(notifier.state.overlayClips.length, 1);
      expect(notifier.state.overlayClips.first.id, clipId);
    });
  });
}
