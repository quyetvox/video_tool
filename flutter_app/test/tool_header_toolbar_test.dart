import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/layouts/top_header.dart';
import 'package:sub_video_desktop/models/video_file.dart';
import 'package:sub_video_desktop/screens/movie_review/components/movie_review_header_bar.dart';
import 'package:sub_video_desktop/screens/movie_review/controllers/movie_review_controller.dart';
import 'package:sub_video_desktop/screens/video_editor/components/video_editor_header_bar.dart';
import 'package:sub_video_desktop/widgets/app_kit.dart';
import 'package:sub_video_desktop/widgets/tool_header_toolbar.dart';

void main() {
  group('ToolHeaderToolbar Widget Tests', () {
    testWidgets('renders title, breadcrumb, and action buttons correctly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool actionClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolHeaderToolbar(
              icon: const Icon(Icons.movie_creation_outlined),
              title: 'Biên Tập & Dịch Video',
              breadcrumb: 'test_video.mp4',
              badge: const Text('Badge Text'),
              actions: [
                ElevatedButton(
                  onPressed: () => actionClicked = true,
                  child: const Text('Action Button'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Biên Tập & Dịch Video'), findsOneWidget);
      expect(find.text('test_video.mp4'), findsOneWidget);
      expect(find.text('Badge Text'), findsOneWidget);
      expect(find.text('Action Button'), findsOneWidget);

      await tester.tap(find.text('Action Button'));
      expect(actionClicked, isTrue);
    });

    testWidgets('VideoEditorHeaderBar renders Voice, Sub, Resume buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool voiceTriggered = false;
      bool subTriggered = false;
      bool resumeTriggered = false;

      const testVideo = VideoFile(
        name: 'test_sample.mp4',
        basename: 'test_sample.mp4',
        relPath: 'src/test_sample.mp4',
        fullPath: '/path/to/src/test_sample.mp4',
        sizeBytes: 1024,
        mtime: 123456.0,
        category: VideoCategory.src,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoEditorHeaderBar(
              selectedVideo: testVideo,
              isProcessing: false,
              onTriggerVoice: () => voiceTriggered = true,
              onTriggerSub: () => subTriggered = true,
              onTriggerResume: () => resumeTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('Biên Tập & Dịch Video'), findsOneWidget);
      expect(find.text('test_sample.mp4'), findsOneWidget);
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Sub'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Voice'));
      expect(voiceTriggered, isTrue);

      await tester.tap(find.text('Sub'));
      expect(subTriggered, isTrue);

      await tester.tap(find.text('Resume'));
      expect(resumeTriggered, isTrue);
    });

    testWidgets('VideoEditorHeaderBar displays Stop button when isProcessing is true', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool stopped = false;

      const testVideo = VideoFile(
        name: 'test_sample.mp4',
        basename: 'test_sample.mp4',
        relPath: 'src/test_sample.mp4',
        fullPath: '/path/to/src/test_sample.mp4',
        sizeBytes: 1024,
        mtime: 123456.0,
        category: VideoCategory.src,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoEditorHeaderBar(
              selectedVideo: testVideo,
              isProcessing: true,
              onTriggerVoice: () {},
              onTriggerSub: () {},
              onTriggerResume: () {},
              onStop: () => stopped = true,
            ),
          ),
        ),
      );

      expect(find.text('Đang xử lý...'), findsOneWidget);
      expect(find.text('Dừng'), findsOneWidget);

      await tester.tap(find.text('Dừng'));
      expect(stopped, isTrue);
    });

    testWidgets('TopHeader renders and toggles sidebar via onToggleSidebar callback', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool sidebarToggled = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TopHeader(
                selectedNavIndex: 0,
                onSelectNav: (_) {},
                onToggleSidebar: () => sidebarToggled = true,
                isSidebarCollapsed: false,
              ),
            ),
          ),
        ),
      );

      // Verify sidebar toggle button with view_sidebar icon
      final toggleFinder = find.byIcon(Icons.view_sidebar);
      expect(toggleFinder, findsOneWidget);

      await tester.tap(toggleFinder);
      expect(sidebarToggled, isTrue);
    });

    testWidgets('AppButton.info renders with sky blue style and handles loading', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton.info(
              icon: Icons.bolt,
              label: 'Test AI',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Test AI'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);

      await tester.tap(find.text('Test AI'));
      expect(tapped, isTrue);
    });

    testWidgets('MovieReviewHeaderBar renders AppButtons with accent and primary variants', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = MovieReviewController();
      controller.selectVideoFromProject(
        projectName: 'test',
        videoPath: '/path/to/movie.mp4',
        videoName: 'movie.mp4',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: MovieReviewHeaderBar(
                state: controller.state,
                controller: controller,
              ),
            ),
          ),
        ),
      );

      expect(find.text('AI Review Phim & Tóm Tắt'), findsOneWidget);
      expect(find.text('movie.mp4'), findsOneWidget);
      expect(find.text('Phân Tích AI'), findsOneWidget);
      expect(find.text('Dựng Video'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.byIcon(Icons.movie_filter_rounded), findsOneWidget);
    });
  });
}
