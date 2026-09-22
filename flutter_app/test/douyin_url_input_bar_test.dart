import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/screens/douyin_downloader/components/douyin_url_input_bar.dart';
import 'package:sub_video_desktop/widgets/internet_video_link_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DouyinUrlInputBar Widget Tests', () {
    testWidgets('renders both batch file selector and InternetVideoLinkBar', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final linkFilePathController = TextEditingController();
      //bool streamPreviewCalled = false;
      //bool videoDownloadedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DouyinUrlInputBar(
              filePathController: linkFilePathController,
              targetDir: '/tmp/test_src',
              onFilePathSubmitted: (_) {},
              onPickLinkFile: () {},
              onStreamPreviewReady: (info) {
                //streamPreviewCalled = true;
              },
              onVideoDownloaded: (filePath, videoName) {
                //videoDownloadedCalled = true;
              },
            ),
          ),
        ),
      );

      // Verify batch file section label
      expect(find.text('Đường dẫn file link (.txt):'), findsOneWidget);
      expect(find.text('Chọn File'), findsOneWidget);

      // Verify single video InternetVideoLinkBar
      expect(find.byType(InternetVideoLinkBar), findsOneWidget);
      expect(find.byIcon(Icons.link_rounded), findsOneWidget);
      expect(find.text('Dán link video Internet (YouTube, TikTok, Douyin, direct link)...'), findsOneWidget);
    });
  });
}
