import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/providers.dart';
import 'package:sub_video_desktop/widgets/video_gizmo_toolbar.dart';

void main() {
  group('VideoGizmoToolbar Widget Tests', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('renders all layer pills, toggle button and reset button', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: VideoGizmoToolbar(),
            ),
          ),
        ),
      );

      expect(find.text('Lớp Căn Chỉnh:'), findsOneWidget);
      expect(find.text('🟦 Inpaint Sub Cũ'), findsOneWidget);
      expect(find.text('🟨 Sub Chính'), findsOneWidget);
      expect(find.text('🔷 Sub Phụ'), findsOneWidget);
      expect(find.text('🟩 Watermark'), findsOneWidget);
      expect(find.text('Hiện Khung Gizmo'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('toggles gizmo active state when toggle button tapped', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: VideoGizmoToolbar(),
            ),
          ),
        ),
      );

      expect(container.read(isGizmoActiveProvider), isFalse);
      expect(find.text('Hiện Khung Gizmo'), findsOneWidget);

      await tester.tap(find.text('Hiện Khung Gizmo'));
      await tester.pump();

      expect(container.read(isGizmoActiveProvider), isTrue);
      expect(find.text('Ẩn Khung Gizmo'), findsOneWidget);

      await tester.tap(find.text('Ẩn Khung Gizmo'));
      await tester.pump();

      expect(container.read(isGizmoActiveProvider), isFalse);
      expect(find.text('Hiện Khung Gizmo'), findsOneWidget);
    });

    testWidgets('tapping layer pill activates gizmo and selects that layer', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: VideoGizmoToolbar(),
            ),
          ),
        ),
      );

      // Default active layer is inpaint
      expect(container.read(activeGizmoLayerProvider), FrameLayerType.inpaint);
      expect(container.read(isGizmoActiveProvider), isFalse);

      // Tap Sub Chính
      await tester.tap(find.text('🟨 Sub Chính'));
      await tester.pump();

      expect(container.read(activeGizmoLayerProvider), FrameLayerType.primarySub);
      expect(container.read(isGizmoActiveProvider), isTrue);

      // Tap Watermark
      await tester.tap(find.text('🟩 Watermark'));
      await tester.pump();

      expect(container.read(activeGizmoLayerProvider), FrameLayerType.watermark);
      expect(container.read(isGizmoActiveProvider), isTrue);
    });

    testWidgets('renders leading widget correctly when provided', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: VideoGizmoToolbar(
                leading: Text('16:9 Aspect Ratio'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('16:9 Aspect Ratio'), findsOneWidget);
      expect(find.text('Lớp Căn Chỉnh:'), findsOneWidget);
    });

    testWidgets('does not change state when enabled is false', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: VideoGizmoToolbar(
                enabled: false,
              ),
            ),
          ),
        ),
      );

      expect(container.read(isGizmoActiveProvider), isFalse);
      await tester.tap(find.text('Hiện Khung Gizmo'));
      await tester.pump();
      expect(container.read(isGizmoActiveProvider), isFalse);

      await tester.tap(find.text('🟨 Sub Chính'));
      await tester.pump();
      expect(container.read(activeGizmoLayerProvider), FrameLayerType.inpaint);
    });
  });
}
