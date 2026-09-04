import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/core/project_manager.dart';

void main() {
  test('ProjectManager resolves nested resources/src/demo path accurately', () {
    final rootDir = Directory.current.parent;
    final paths = ProjectManager.resolveProjectPaths(
      'resources/src/demo/video.mp4',
      rootDirOverride: rootDir,
    );
    expect(paths.projectName, equals('demo'));
  });

  test('ProjectManager resolves standard resources/anh_trang_sang project', () {
    final rootDir = Directory.current.parent;
    final paths = ProjectManager.resolveProjectPaths(
      'resources/anh_trang_sang/src/anh_trang_sang.mp4',
      rootDirOverride: rootDir,
    );
    expect(paths.projectName, equals('anh_trang_sang'));
  });
}
