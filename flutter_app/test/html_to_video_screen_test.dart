import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/providers.dart';
import 'package:sub_video_desktop/screens/html_to_video/html_to_video_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HtmlToVideoScreen Widget Tests', () {
    testWidgets('renders Timeline Lock switch and toggles correctly', (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRootProvider.overrideWith((ref) => '/tmp'),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: HtmlToVideoScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Timeline Lock switch exists
      final switchFinder = find.widgetWithText(SwitchListTile, 'Khóa Timeline (Timeline Lock)');
      await tester.scrollUntilVisible(switchFinder, 200, scrollable: find.byType(Scrollable).first);
      expect(switchFinder, findsOneWidget);

      // Verify default state is False (Auto Mode)
      SwitchListTile switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isFalse);
      expect(find.textContaining('Tắt (Auto): Audio làm chuẩn thời gian (Master)'), findsOneWidget);

      // Tap to toggle
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Verify state becomes True (Timeline Locked)
      switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);
      expect(find.textContaining('Bật: Khóa đúng mốc slot [start - end]'), findsOneWidget);

      // Switch to Tab 2 (🎙️ Thuyết Minh & Audio) and verify Speed Slider (0.5x -> 2.0x)
      await tester.tap(find.text('🎙️ Thuyết Minh & Audio'));
      await tester.pumpAndSettle();

      expect(find.text('Tốc độ đọc mặc định (Speed)'), findsOneWidget);
      expect(find.text('1.00x'), findsOneWidget);

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);
      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.min, 0.5);
      expect(slider.max, 2.0);

      // Verify Ban Mai voice option exists in Primary Voice dropdown
      await tester.tap(find.textContaining('Hoài My').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Ban Mai'), findsWidgets);
    });
  });
}
