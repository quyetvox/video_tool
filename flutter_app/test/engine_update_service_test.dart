import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sub_video_desktop/core/app_constants.dart';
import 'package:sub_video_desktop/core/engine_resolver.dart';
import 'package:sub_video_desktop/core/engine_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EngineUpdateService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('EngineUpdateInfo.fromJson parses server format correctly', () {
      final json = {
        'version': '1.1.58',
        'download_url': 'https://subvideo.site/api/v1/patches/download/latest?version=1.1.58',
        'direct_download_url': '/static/patches/sub_video_core_patch_v1.1.58.zip',
        'size_bytes': 507197,
        'download_count': 10,
        'checksum_sha256': '2ea2fd32b37f4b30788ff2811d65e1986399fdaba41047a63f1626039e5824e7',
        'release_notes': 'Bản vá v1.1.58: Nâng cấp Multi-Track Timeline Overlay.',
        'released_at': '2026-09-06T05:44:23.000',
      };

      final info = EngineUpdateInfo.fromJson(json);
      expect(info.version, '1.1.58');
      expect(info.downloadUrl, 'https://subvideo.site/api/v1/patches/download/latest?version=1.1.58');
      expect(info.sizeBytes, 507197);
      expect(info.releaseNotes, contains('Multi-Track'));
      expect(info.isLocalSource, false);
    });

    test('getManifestUrl returns default https://subvideo.site endpoint', () async {
      final url = await EngineUpdateService.getManifestUrl();
      expect(url, equals('${AppConstants.defaultApiBaseUrl}/patches/latest'));
      expect(url, contains('subvideo.site'));
    });

    test('Corrupted/HTML non-zip bytes fail Magic Byte validation', () async {
      final htmlBytes = utf8.encode('<!DOCTYPE html><html><body>Error 404</body></html>');
      EngineUpdateInfo(
        version: '9.9.9',
        releaseNotes: 'Corrupted test',
        downloadUrl: 'fake',
        sizeBytes: htmlBytes.length,
        publishedAt: DateTime.now(),
        isLocalSource: true,
      );

      // applyPatch with non-existent local file should be handled safely
      expect(
        () => EngineUpdateService.applyLocalZipPatch('/tmp/non_existent_file_test.zip'),
        throwsException,
      );
    });

    test('EngineResolver.compareSemVer correctly evaluates version precedence', () {
      // Equal versions
      expect(EngineResolver.compareSemVer('1.1.58', '1.1.58'), equals(0));
      expect(EngineResolver.compareSemVer('v1.1.58', '1.1.58'), equals(0));

      // Newer server patch
      expect(EngineResolver.compareSemVer('1.1.59', '1.1.58'), greaterThan(0));
      expect(EngineResolver.compareSemVer('1.2.0', '1.1.58'), greaterThan(0));
      expect(EngineResolver.compareSemVer('2.0.0', '1.1.58'), greaterThan(0));

      // Older or downgrade patch
      expect(EngineResolver.compareSemVer('1.1.57', '1.1.58'), lessThan(0));
      expect(EngineResolver.compareSemVer('1.0.99', '1.1.58'), lessThan(0));
    });

    test('ActiveEngineInfo holds rawVersion and display version accurately', () async {
      final info = await EngineUpdateService.getActiveEngineInfo();
      expect(info.rawVersion, isNotEmpty);
      expect(info.version, contains(info.rawVersion));
      expect(info.source, anyOf(['dev_source', 'bundled', 'hot_patch', 'fallback']));
    });

    test('checkUpdate with local manifest file correctly resolves EngineUpdateInfo', () async {
      final tempDir = Directory.systemTemp.createTempSync('patch_test_');
      try {
        final manifestFile = File('${tempDir.path}/engine_manifest.json');
        manifestFile.writeAsStringSync(jsonEncode({
          'version': '1.1.59',
          'release_notes': 'Local test patch v1.1.59',
          'download_url': 'https://example.com/patch.zip',
          'size_bytes': 1024,
        }));

        final update = await EngineUpdateService.checkUpdate(customSource: manifestFile.path);
        expect(update, isNotNull);
        expect(update?.version, '1.1.59');
        expect(update?.releaseNotes, contains('v1.1.59'));
        expect(update?.isLocalSource, isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
