import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/widgets/resizable_collapsible_panel.dart';

void main() {
  group('ResizableCollapsiblePanel Tests', () {
    testWidgets('Vertical bottom panel renders and respects initialHeight', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: ResizableCollapsiblePanel(
                side: PanelSide.bottom,
                initialHeight: 250.0,
                minHeight: 120.0,
                maxHeight: 450.0,
                panel: SizedBox(
                  key: Key('panel_widget'),
                  child: Text('Panel Content'),
                ),
                child: SizedBox(
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

    testWidgets('Horizontal left drawer panel supports GlobalKey programmatic control', (tester) async {
      final panelKey = GlobalKey<ResizableCollapsiblePanelState>();
      bool? collapsedState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 600,
              child: ResizableCollapsiblePanel(
                key: panelKey,
                side: PanelSide.left,
                initialWidth: 250.0,
                minWidth: 180.0,
                maxWidth: 380.0,
                onCollapseChanged: (c) => collapsedState = c,
                panel: const Text('Drawer Sidebar Content'),
                child: const Text('Main Screen Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Drawer Sidebar Content'), findsOneWidget);
      expect(find.text('Main Screen Content'), findsOneWidget);
      expect(panelKey.currentState?.isCollapsed, isFalse);

      // Programmatic collapse
      panelKey.currentState?.collapse();
      await tester.pumpAndSettle();
      expect(panelKey.currentState?.isCollapsed, isTrue);
      expect(collapsedState, isTrue);

      // Programmatic expand
      panelKey.currentState?.expand();
      await tester.pumpAndSettle();
      expect(panelKey.currentState?.isCollapsed, isFalse);
      expect(collapsedState, isFalse);

      // Programmatic toggleCollapse
      panelKey.currentState?.toggleCollapse();
      await tester.pumpAndSettle();
      expect(panelKey.currentState?.isCollapsed, isTrue);
    });

    testWidgets('Horizontal left panel dragging updates width', (tester) async {
      double? updatedWidth;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 600,
              child: ResizableCollapsiblePanel(
                side: PanelSide.left,
                initialWidth: 250.0,
                minWidth: 180.0,
                maxWidth: 380.0,
                onWidthChanged: (w) => updatedWidth = w,
                panel: const Text('Drawer Sidebar'),
                child: const Text('Main App'),
              ),
            ),
          ),
        ),
      );

      // Drag divider right by 60px (should increase left panel width to 310)
      final dividerFinder = find.byType(GestureDetector).first;
      await tester.drag(dividerFinder, const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(updatedWidth, isNotNull);
      expect(updatedWidth!, greaterThan(250.0));
    });
  });
}
