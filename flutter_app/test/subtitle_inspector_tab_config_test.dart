import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sub_video_desktop/widgets/subtitle_inspector_widget.dart';

void main() {
  group('SubtitleInspectorWidget Tab Configuration Tests', () {
    testWidgets('Vlog Story mode: customScriptTab at Index 0 and showLongVideoTab = false', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SubtitleInspectorWidget(
                subtitles: const [],
                currentTime: 0.0,
                onSubtitleChange: (_) {},
                onTranslateAll: () {},
                onAutoSync: () {},
                onSaveSubtitles: () {},
                showLongVideoTab: false,
                customScriptTabTitle: '📖 Kịch bản AI',
                customScriptTab: const Center(
                  child: Text('Nội dung cấu hình kịch bản AI Vlog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify Tab 0 is '📖 Kịch bản AI'
      expect(find.text('📖 Kịch bản AI'), findsOneWidget);
      expect(find.text('Nội dung cấu hình kịch bản AI Vlog'), findsOneWidget);

      // Verify standard tabs exist
      expect(find.text('📝 Subtitles'), findsOneWidget);
      expect(find.text('📐 Subtitle Style'), findsOneWidget);
      expect(find.text('🖼️ Inpaint'), findsOneWidget);
      expect(find.text('🎙️ Voice & Audio'), findsOneWidget);
      expect(find.text('⚙️ Video & Engine'), findsOneWidget);

      // Verify '✂️ Video Dài' is suppressed
      expect(find.text('✂️ Video Dài'), findsNothing);
    });

    testWidgets('Standard Video Editor mode: default tabs with Video Dài tab enabled', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SubtitleInspectorWidget(
                subtitles: const [],
                currentTime: 0.0,
                onSubtitleChange: (_) {},
                onTranslateAll: () {},
                onAutoSync: () {},
                onSaveSubtitles: () {},
              ),
            ),
          ),
        ),
      );

      // Tab 0 should be '📝 Subtitles'
      expect(find.text('📝 Subtitles'), findsOneWidget);
      expect(find.text('📐 Subtitle Style'), findsOneWidget);
      expect(find.text('🖼️ Inpaint'), findsOneWidget);
      expect(find.text('🎙️ Voice & Audio'), findsOneWidget);
      expect(find.text('⚙️ Video & Engine'), findsOneWidget);
      expect(find.text('✂️ Video Dài'), findsOneWidget);
      expect(find.text('📖 Kịch bản AI'), findsNothing);
    });
  });
}
