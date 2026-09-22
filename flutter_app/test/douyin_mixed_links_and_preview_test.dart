import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/douyin_video_item.dart';
import 'package:sub_video_desktop/screens/douyin_downloader/components/douyin_preview_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DouyinVideoItem Mixed Links Parsing Tests', () {
    test('parses Bilibili URL correctly with BV shortHash and Bilibili resolution', () {
      const raw = 'https://www.bilibili.com/video/BV1VSYX6xE5y/?trackid=web_pegasus_0.router-web-pegasus-2479516-gfll4.1790048850192.912';
      final item = DouyinVideoItem.parse(raw, 0);

      expect(item, isNotNull);
      expect(item!.resolution, equals('Bilibili'));
      expect(item.shortHash, equals('BV1VSYX6xE5y'));
      expect(item.filename, equals('BV1VSYX6xE5y.mp4'));
      expect(item.isDownloaded, isFalse);
      expect(item.isProbed, isFalse);
    });

    test('parses YouTube URL correctly with video ID and YouTube resolution', () {
      const raw = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      final item = DouyinVideoItem.parse(raw, 1);

      expect(item, isNotNull);
      expect(item!.resolution, equals('YouTube'));
      expect(item.shortHash, equals('dQw4w9WgXcQ'));
      expect(item.filename, equals('dQw4w9WgXcQ.mp4'));
    });

    test('parses Douyin web share URL with Douyin resolution', () {
      const raw = 'https://www.douyin.com/video/7392819283918291029';
      final item = DouyinVideoItem.parse(raw, 2);

      expect(item, isNotNull);
      expect(item!.resolution, equals('Douyin'));
    });

    test('copyWith updates title, isProbed, directUrl, audioUrl and httpHeaders properly', () {
      const raw = 'https://www.bilibili.com/video/BV1VSYX6xE5y/';
      final item = DouyinVideoItem.parse(raw, 0)!;

      final updated = item.copyWith(
        directUrl: 'https://upos-stream.example.com/video.m4s',
        audioUrl: 'https://upos-stream.example.com/audio.m4s',
        httpHeaders: {'Referer': raw},
        title: 'Tiêu Đề Bilibili Tuyệt Đẹp',
        filename: 'Tieu_De_Bilibili.mp4',
        resolution: '08:42',
        isProbed: true,
      );

      expect(updated.directUrl, equals('https://upos-stream.example.com/video.m4s'));
      expect(updated.audioUrl, equals('https://upos-stream.example.com/audio.m4s'));
      expect(updated.httpHeaders?['Referer'], equals(raw));
      expect(updated.title, equals('Tiêu Đề Bilibili Tuyệt Đẹp'));
      expect(updated.filename, equals('Tieu_De_Bilibili.mp4'));
      expect(updated.resolution, equals('08:42'));
      expect(updated.isProbed, isTrue);
    });
  });

  group('DouyinPreviewPanel Widget Tests', () {
    testWidgets('renders probing loading state when isProbing is true', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const raw = 'https://www.bilibili.com/video/BV1VSYX6xE5y/';
      final item = DouyinVideoItem.parse(raw, 0)!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DouyinPreviewPanel(
              selectedItem: item,
              activeProject: 'test_project',
              onDownloadSingle: (_) {},
              isProbing: true,
            ),
          ),
        ),
      );

      expect(find.text('⚡ Đang bóc tách luồng xem trước...'), findsOneWidget);
      expect(find.text('Trích xuất video & âm thanh trực tuyến (Live CDN Stream)...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders probe error state with retry button when probeError is set', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const raw = 'https://www.bilibili.com/video/BV1VSYX6xE5y/';
      final item = DouyinVideoItem.parse(raw, 0)!;
      bool retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DouyinPreviewPanel(
              selectedItem: item,
              activeProject: 'test_project',
              onDownloadSingle: (_) {},
              isProbing: false,
              probeError: 'Video bị giới hạn vùng quốc gia hoặc bản quyền',
              onRetryProbe: () {
                retried = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Không thể bóc tách luồng xem trước'), findsOneWidget);
      expect(find.text('Video bị giới hạn vùng quốc gia hoặc bản quyền'), findsOneWidget);
      expect(find.text('Thử Lại'), findsOneWidget);

      await tester.tap(find.text('Thử Lại'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });
}
