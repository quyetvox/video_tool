import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/providers.dart';
import 'package:sub_video_desktop/models/video_file.dart';
import 'package:sub_video_desktop/screens/vlog_story/vlog_story_screen.dart';
import 'package:sub_video_desktop/widgets/internet_video_link_bar.dart';
import 'package:sub_video_desktop/widgets/video_gizmo_toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VlogStoryScreen Widget Tests', () {
    testWidgets('renders VideoGizmoToolbar and clean video canvas without InternetVideoLinkBar', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectVideosProvider.overrideWith((ref) => {
              'srcFiles': <VideoFile>[],
              'cutFiles': <VideoFile>[],
              'mergeFiles': <VideoFile>[],
              'outputFiles': <VideoFile>[],
            }),
          ],
          child: const MaterialApp(
            home: VlogStoryScreen(),
          ),
        ),
      );

      // Verify VideoGizmoToolbar is rendered on screen
      expect(find.byType(VideoGizmoToolbar), findsOneWidget);
      expect(find.text('Lớp Căn Chỉnh:'), findsOneWidget);
      expect(find.text('🟦 Inpaint Sub Cũ'), findsOneWidget);
      expect(find.text('🟨 Sub Chính'), findsOneWidget);

      // Verify InternetVideoLinkBar is NOT rendered (moved to Douyin Downloader tab)
      expect(find.byType(InternetVideoLinkBar), findsNothing);
      expect(find.text('Chọn video từ danh sách bên trái để bắt đầu'), findsOneWidget);
    });
  });
}
