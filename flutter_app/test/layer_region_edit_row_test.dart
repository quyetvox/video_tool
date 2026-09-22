import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/providers.dart';
import 'package:sub_video_desktop/widgets/layer_region_edit_row.dart';

void main() {
  group('LayerRegionEditRow 2-Way Coordinate Sync & Activation Tests', () {
    testWidgets('Tapping Chỉnh in LayerRegionEditRow activates gizmo and syncs activeGizmoLayerProvider', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Start with primarySub to verify layer switching
      container.read(activeGizmoLayerProvider.notifier).state = FrameLayerType.primarySub;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: LayerRegionEditRow(
                label: 'Vùng Xóa Sub Cũ:',
                region: const [0.58, 0.08, 0.64, 0.94],
                layerType: FrameLayerType.inpaint,
                onReset: () {},
              ),
            ),
          ),
        ),
      );

      // Initially inactive
      expect(container.read(isGizmoActiveProvider), false);
      expect(container.read(activeGizmoLayerProvider), FrameLayerType.primarySub);
      expect(find.text('🎯 Chỉnh'), findsOneWidget);

      // Tap Chỉnh
      await tester.tap(find.text('🎯 Chỉnh'));
      await tester.pumpAndSettle();

      // Now active
      expect(container.read(isGizmoActiveProvider), true);
      expect(container.read(activeGizmoLayerProvider), FrameLayerType.inpaint);
      expect(find.text('✓ Đang Chỉnh'), findsOneWidget);

      // Tap again to toggle off
      await tester.tap(find.text('✓ Đang Chỉnh'));
      await tester.pumpAndSettle();

      expect(container.read(isGizmoActiveProvider), false);
      expect(find.text('🎯 Chỉnh'), findsOneWidget);
    });

    testWidgets('Tapping Auto triggers onReset callback', (tester) async {
      bool resetCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LayerRegionEditRow(
                label: 'Vị Trí Sub Chính:',
                region: const [0.76, 0.05, 0.86, 0.95],
                layerType: FrameLayerType.primarySub,
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

    testWidgets('Displays formatted percentages and 4 micro inputs with safety bounds', (tester) async {
      List<double>? updatedRegion;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LayerRegionEditRow(
                label: 'Vùng Đặt Watermark:',
                region: const [0.02, 0.85, 0.05, 0.95],
                layerType: FrameLayerType.watermark,
                onRegionChanged: (r) {
                  updatedRegion = r;
                },
                onReset: () {},
              ),
            ),
          ),
        ),
      );

      // Formatted percentages in monospace container
      expect(find.text('2.0%, 85.0%, 5.0%, 95.0%'), findsOneWidget);

      // Micro input tags exist
      expect(find.text('Y1'), findsOneWidget);
      expect(find.text('X1'), findsOneWidget);
      expect(find.text('Y2'), findsOneWidget);
      expect(find.text('X2'), findsOneWidget);

      // Submit new valid value in Y1 (index 0)
      final y1Finder = find.widgetWithText(TextFormField, '2.0');
      expect(y1Finder, findsOneWidget);
      await tester.enterText(y1Finder, '3.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(updatedRegion, isNotNull);
      expect(updatedRegion![0], 0.035);
      expect(updatedRegion![1], 0.85);
      expect(updatedRegion![2], 0.05);
      expect(updatedRegion![3], 0.95);
    });

    testWidgets('Enforces bounding box constraints when Y1 exceeds Y2', (tester) async {
      List<double>? updatedRegion;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: LayerRegionEditRow(
                label: 'Vùng Đặt Watermark:',
                region: const [0.02, 0.85, 0.05, 0.95],
                layerType: FrameLayerType.watermark,
                onRegionChanged: (r) {
                  updatedRegion = r;
                },
                onReset: () {},
              ),
            ),
          ),
        ),
      );

      // Enter Y1 = 6.0% (which exceeds Y2 = 5.0%)
      final y1Finder = find.widgetWithText(TextFormField, '2.0');
      await tester.enterText(y1Finder, '6.0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(updatedRegion, isNotNull);
      // Y1 is safely clamped to Y2 - 0.02 = 0.05 - 0.02 = 0.03
      expect(updatedRegion![0], 0.03);
      expect(updatedRegion![2], 0.05);
    });
  });
}
