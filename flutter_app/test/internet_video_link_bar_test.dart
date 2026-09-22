import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/models/media_link_info.dart';
import 'package:sub_video_desktop/widgets/internet_video_link_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InternetVideoLinkBar Widget Tests', () {
    testWidgets('renders TextField and link icon correctly in idle state', (tester) async {
      final key = GlobalKey<InternetVideoLinkBarState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InternetVideoLinkBar(
              key: key,
              targetDir: '/tmp/test_dir',
              customProber: (url) async => MediaLinkInfo(
                success: true,
                rawUrl: url,
                title: 'Test Movie',
                streamUrl: 'https://example.com/stream.mp4',
              ),
            ),
          ),
        ),
      );

      // Verify hint text and link icon
      expect(find.byIcon(Icons.link_rounded), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Dán link video Internet (YouTube, TikTok, Douyin, direct link)...'), findsOneWidget);

      // Verify state is idle
      expect(key.currentState?.isPreviewing, isFalse);
      expect(key.currentState?.isDownloading, isFalse);
    });

    testWidgets('typing and calling reset clears text and restores idle state', (tester) async {
      final key = GlobalKey<InternetVideoLinkBarState>();
      bool clearedCalled = false;
      MediaLinkInfo? previewInfo;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InternetVideoLinkBar(
              key: key,
              targetDir: '/tmp/test_dir',
              customProber: (url) async => MediaLinkInfo(
                success: true,
                rawUrl: url,
                title: 'Test Video',
                duration: 120.0,
                streamUrl: 'https://example.com/stream.mp4',
              ),
              onStreamPreviewReady: (info) {
                previewInfo = info;
              },
              onCleared: () {
                clearedCalled = true;
              },
            ),
          ),
        ),
      );

      // Enter a link
      await tester.enterText(find.byType(TextField), 'https://example.com/test.mp4');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Stream preview should be ready and badge visible
      expect(previewInfo?.streamUrl, 'https://example.com/stream.mp4');
      expect(find.text('Test Video'), findsOneWidget);
      expect(key.currentState?.isPreviewing, isTrue);

      // Clear icon (X) should be visible
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Call external reset
      key.currentState?.reset();
      await tester.pump();

      expect(find.text('https://example.com/test.mp4'), findsNothing);
      expect(clearedCalled, isTrue);
      expect(key.currentState?.isPreviewing, isFalse);
    });
  });
}
