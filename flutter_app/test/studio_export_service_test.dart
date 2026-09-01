import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sub_video_desktop/core/studio_export_service.dart';

void main() {
  group('StudioExportService Tests', () {
    test('ensureDirectories creates cut, merge, and output folders', () async {
      final tempDir = Directory.systemTemp.createTempSync('studio_export_test_');
      try {
        final dirs = await StudioExportService.ensureDirectories(tempDir.path);
        expect(dirs.containsKey('cut'), true);
        expect(dirs.containsKey('merge'), true);
        expect(dirs.containsKey('output'), true);

        expect(await Directory(p.join(tempDir.path, 'cut')).exists(), true);
        expect(await Directory(p.join(tempDir.path, 'merge')).exists(), true);
        expect(await Directory(p.join(tempDir.path, 'output')).exists(), true);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
