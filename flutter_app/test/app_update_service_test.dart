import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/app_update_service.dart';

void main() {
  group('AppUpdateService SemVer and Release Tests', () {
    test('compareSemVer correctly compares version strings', () {
      expect(AppUpdateService.compareSemVer('v1.0.1', 'v1.0.0'), greaterThan(0));
      expect(AppUpdateService.compareSemVer('1.1.0', '1.0.9'), greaterThan(0));
      expect(AppUpdateService.compareSemVer('v2.0.0', 'v1.9.99'), greaterThan(0));
      expect(AppUpdateService.compareSemVer('1.0.0', 'v1.0.0'), equals(0));
      expect(AppUpdateService.compareSemVer('v1.0.0', 'v1.0.1'), lessThan(0));
      expect(AppUpdateService.compareSemVer('v1.0.0', 'v2.0.0'), lessThan(0));
    });

    test('AppUpdateRelease.fromJson correctly parses assets for current platform', () {
      final mockJson = {
        'tag_name': 'v1.1.0',
        'name': 'Sub-Video AI v1.1.0 Release',
        'body': 'Changelog: added auto update support',
        'html_url': 'https://github.com/example/releases/tag/v1.1.0',
        'published_at': '2026-09-04T12:00:00Z',
        'assets': [
          {
            'name': 'SubVideo_AI_Windows_x64_Setup_v1.1.0.exe',
            'browser_download_url': 'https://github.com/example/releases/download/v1.1.0/SubVideo_AI_Windows_x64_Setup_v1.1.0.exe',
            'size': 65000000,
          },
          {
            'name': 'SubVideo-AI-Windows-x64-Portable-v1.1.0.zip',
            'browser_download_url': 'https://github.com/example/releases/download/v1.1.0/SubVideo-AI-Windows-x64-Portable-v1.1.0.zip',
            'size': 60000000,
          },
          {
            'name': 'SubVideo-AI-macOS-arm64-v1.1.0.dmg',
            'browser_download_url': 'https://github.com/example/releases/download/v1.1.0/SubVideo-AI-macOS-arm64-v1.1.0.dmg',
            'size': 75000000,
          },
        ],
      };

      final release = AppUpdateRelease.fromJson(mockJson);
      expect(release.tagName, 'v1.1.0');
      expect(release.version, '1.1.0');
      expect(release.releaseNotes, contains('Changelog'));
      expect(release.htmlUrl, 'https://github.com/example/releases/tag/v1.1.0');

      if (Platform.isMacOS) {
        expect(release.assetName, 'SubVideo-AI-macOS-arm64-v1.1.0.dmg');
        expect(release.assetDownloadUrl, contains('.dmg'));
        expect(release.assetSizeBytes, 75000000);
      } else if (Platform.isWindows) {
        expect(release.assetName, 'SubVideo_AI_Windows_x64_Setup_v1.1.0.exe');
        expect(release.assetDownloadUrl, contains('.exe'));
        expect(release.assetSizeBytes, 65000000);
      }
    });

    test('AppUpdateRelease.fromJson filters out releases for other platforms', () {
      final oppositeJson = {
        'tag_name': 'v1.2.0',
        'assets': [
          if (Platform.isMacOS)
            {
              'name': 'SubVideo_AI_Windows_x64_Setup_v1.2.0.exe',
              'browser_download_url': 'https://example.com/win.exe',
            }
          else
            {
              'name': 'SubVideo-AI-macOS-arm64-v1.2.0.dmg',
              'browser_download_url': 'https://example.com/mac.dmg',
            }
        ]
      };
      final release = AppUpdateRelease.fromJson(oppositeJson);
      expect(release.assetDownloadUrl, isNull);
    });
  });
}
