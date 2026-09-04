import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/ai_environment_service.dart';

void main() {
  group('AiEnvironmentService Tests', () {
    test('aiRuntimeDir is valid and placed in user profile/appdata sandbox', () {
      final dir = AiEnvironmentService.aiRuntimeDir;
      expect(dir.path, isNotEmpty);
      expect(dir.path.contains('ai_runtime'), isTrue);

      if (Platform.isWindows) {
        expect(
          dir.path.contains('AppData') || dir.path.contains('.subvideo'),
          isTrue,
          reason: 'On Windows, ai_runtime must be in user AppData sandbox, never Program Files',
        );
      } else if (Platform.isMacOS) {
        expect(
          dir.path.contains('Library/Application Support/SubVideo') || dir.path.contains('.subvideo'),
          isTrue,
          reason: 'On macOS, ai_runtime must be in Application Support or user home',
        );
      }
    });

    test('sitePackagesDir is inside aiRuntimeDir', () {
      final sitePackages = AiEnvironmentService.sitePackagesDir;
      expect(sitePackages.path.endsWith('site-packages'), isTrue);
      expect(sitePackages.parent.path, equals(AiEnvironmentService.aiRuntimeDir.path));
    });

    test('getDownloadUrl returns platform-specific zip asset', () {
      final url = AiEnvironmentService.getDownloadUrl();
      expect(url.startsWith('https://'), isTrue);
      expect(url.endsWith('.zip'), isTrue);

      if (Platform.isWindows) {
        expect(url.contains('Win64'), isTrue);
      } else {
        expect(url.contains('macOS'), isTrue);
      }
    });

    test('isAiReady does not throw and returns boolean', () async {
      final isReady = await AiEnvironmentService.isAiReady();
      expect(isReady, isA<bool>());
    });
  });
}
