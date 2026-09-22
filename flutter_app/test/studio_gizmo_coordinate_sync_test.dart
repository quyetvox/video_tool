import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/providers.dart';
import 'package:sub_video_desktop/core/studio_state_notifier.dart';
import 'package:sub_video_desktop/screens/video_studio/components/properties/studio_region_edit_row.dart';

void main() {
  group('Studio Gizmo 2-Way Coordinate Sync & Activation Tests', () {
    testWidgets('Tapping Chỉnh in StudioRegionEditRow activates gizmo and syncs both studio and global providers', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StudioRegionEditRow(
                label: 'Tọa Độ Inpaint:',
                region: const [0.72, 0.05, 0.88, 0.95],
                layerType: StudioGizmoLayer.inpaint,
                onReset: () {},
              ),
            ),
          ),
        ),
      );

      // Initially inactive
      expect(container.read(isGizmoActiveProvider), false);
      expect(container.read(activeStudioGizmoLayerProvider), StudioGizmoLayer.none);
      expect(find.text('🎯 Chỉnh'), findsOneWidget);

      // Tap Chỉnh
      await tester.tap(find.text('🎯 Chỉnh'));
      await tester.pumpAndSettle();

      // Now active in both providers
      expect(container.read(isGizmoActiveProvider), true);
      expect(container.read(activeStudioGizmoLayerProvider), StudioGizmoLayer.inpaint);
      expect(container.read(activeGizmoLayerProvider), FrameLayerType.inpaint);
      expect(find.text('✓ Đang Chỉnh'), findsOneWidget);

      // Tap again to toggle off
      await tester.tap(find.text('✓ Đang Chỉnh'));
      await tester.pumpAndSettle();

      expect(container.read(isGizmoActiveProvider), false);
      expect(container.read(activeStudioGizmoLayerProvider), StudioGizmoLayer.none);
      expect(find.text('🎯 Chỉnh'), findsOneWidget);
    });

    testWidgets('Tapping Auto triggers onReset callback', (tester) async {
      bool resetCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioRegionEditRow(
                label: 'Tọa Độ Sub Chính:',
                region: const [0.76, 0.05, 0.86, 0.95],
                layerType: StudioGizmoLayer.primarySub,
                onReset: () {
                  resetCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();

      expect(resetCalled, true);
    });

    testWidgets('Displays 4 mini coordinate inputs when onRegionChanged is provided', (tester) async {
      List<double>? changedRegion;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: StudioRegionEditRow(
                label: 'Tọa Độ Watermark:',
                region: const [0.02, 0.85, 0.50, 0.95],
                layerType: StudioGizmoLayer.watermark,
                onRegionChanged: (r) {
                  changedRegion = r;
                },
                onReset: () {},
              ),
            ),
          ),
        ),
      );

      // Verify mini tags
      expect(find.text('Y1'), findsOneWidget);
      expect(find.text('X1'), findsOneWidget);
      expect(find.text('Y2'), findsOneWidget);
      expect(find.text('X2'), findsOneWidget);

      // Verify initial percentages formatted
      expect(find.text('2.0'), findsOneWidget);
      expect(find.text('85.0'), findsOneWidget);
      expect(find.text('50.0'), findsOneWidget);
      expect(find.text('95.0'), findsOneWidget);

      // Enter new coordinate in Y1
      await tester.enterText(find.widgetWithText(TextFormField, '2.0'), '10.0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(changedRegion, isNotNull);
      expect(changedRegion![0], closeTo(0.10, 0.001));
      expect(changedRegion![1], closeTo(0.85, 0.001));
    });

    test('StudioStateNotifier updateRegion methods clamp properly for all 4 layers', () {
      final notifier = StudioStateNotifier();

      // 1. Inpaint
      notifier.updateInpaintRegion([0.5, 0.1, 0.6, 0.9]);
      expect(notifier.state.inpaintConfig.region, [0.5, 0.1, 0.6, 0.9]);

      // 2. Primary Sub
      notifier.updateSubtitleRegion([0.75, 0.08, 0.85, 0.92]);
      expect(notifier.state.subStyle.subtitleRegion, [0.75, 0.08, 0.85, 0.92]);
      expect(notifier.state.subStyle.posY, 75.0);

      // 3. Secondary Sub
      notifier.updateSubtitleSecondaryRegion([0.86, 0.08, 0.94, 0.92]);
      expect(notifier.state.subStyle.subtitleSecondaryRegion, [0.86, 0.08, 0.94, 0.92]);
      expect(notifier.state.subStyle.secPosY, 86.0);

      // 4. Watermark
      notifier.updateWatermarkRegion([0.03, 0.80, 0.08, 0.95]);
      expect(notifier.state.inpaintConfig.watermarkRegion, [0.03, 0.80, 0.08, 0.95]);
    });
  });
}
