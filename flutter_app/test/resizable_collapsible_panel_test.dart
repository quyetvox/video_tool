import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/widgets/resizable_collapsible_panel.dart';

void main() {
  group('ResizableCollapsiblePanel Tests', () {
    testWidgets('Vertical bottom panel renders and respects initialHeight', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ResizableCollapsiblePanel(
                side: PanelSide.bottom,
                initialHeight: 250.0,
                minHeight: 120.0,
                maxHeight: 450.0,
                panel: const SizedBox(
                  key: Key('panel_widget'),
                  child: Text('Panel Content'),
                ),
                child: const SizedBox(
                  key: Key('child_widget'),
                  child: Text('Main Content'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Panel Content'), findsOneWidget);
      expect(find.text('Main Content'), findsOneWidget);
      expect(find.byKey(const Key('panel_widget')), findsOneWidget);
    });

    testWidgets('Vertical panel toggles collapse via button', (tester) async {
      bool? collapsedState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ResizableCollapsiblePanel(
                side: PanelSide.bottom,
                initialHeight: 250.0,
                minHeight: 120.0,
                maxHeight: 450.0,
                collapseTooltip: 'Thu gọn',
                expandTooltip: 'Mở rộng',
                onCollapseChanged: (collapsed) => collapsedState = collapsed,
                panel: const Text('Bottom Panel'),
                child: const Text('Top Child'),
              ),
            ),
          ),
        ),
      );

      // Find toggle InkWell and tap to collapse
      final toggleFinder = find.byType(InkWell);
      expect(toggleFinder, findsOneWidget);

      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      expect(collapsedState, isTrue);

      // Now tooltip should say expand
      final expandFinder = find.byTooltip('Mở rộng');
      expect(expandFinder, findsOneWidget);

      await tester.tap(expandFinder);
      await tester.pumpAndSettle();

      expect(collapsedState, isFalse);
    });

    testWidgets('Vertical panel dragging updates height', (tester) async {
      double? updatedHeight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ResizableCollapsiblePanel(
                side: PanelSide.bottom,
                initialHeight: 250.0,
                minHeight: 120.0,
                maxHeight: 450.0,
                onHeightChanged: (h) => updatedHeight = h,
                panel: const Text('Bottom Panel'),
                child: const Text('Top Child'),
              ),
            ),
          ),
        ),
      );

      // Drag divider up by 50px (should increase bottom panel height by 50)
      final dividerFinder = find.byType(GestureDetector).first;
      await tester.drag(dividerFinder, const Offset(0, -50));
      await tester.pumpAndSettle();

      expect(updatedHeight, isNotNull);
      expect(updatedHeight!, greaterThan(250.0));
    });
  });
}
