import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../core/python_bridge.dart';
import '../../../../widgets/app_kit.dart';
import '../models/movie_review_model.dart';

class ScenePickerDialog extends StatelessWidget {
  final List<SceneMeta> availableScenes;
  final String videoName;
  final String projectName;
  final ValueChanged<SceneMeta> onSceneSelected;

  const ScenePickerDialog({
    super.key,
    required this.availableScenes,
    required this.videoName,
    required this.projectName,
    required this.onSceneSelected,
  });

  String get _keyframesDirPath {
    final root = PythonBridge.resolveRootDir();
    final safeName = p.withoutExtension(videoName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    return p.join(root, 'resources', projectName, 'workspace', 'movie_review', safeName, 'keyframes');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      child: Container(
        width: 750,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.collections_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text(
                  'Kho Cảnh Minh Họa Phim (Keyframes)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    'Tổng: ${availableScenes.length} cảnh',
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: c.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Đóng',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Chọn phân cảnh bạn muốn gán làm B-roll minh họa cho câu thoại này:',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            const SizedBox(height: 16),

            // Grid Keyframes
            Expanded(
              child: availableScenes.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có cảnh nào được quét. Hãy chạy Phân tích video trước.',
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.35,
                      ),
                      itemCount: availableScenes.length,
                      itemBuilder: (context, index) {
                        final sc = availableScenes[index];
                        final imgFile = File(p.join(_keyframesDirPath, sc.imagePath));

                        return InkWell(
                          onTap: () {
                            onSceneSelected(sc);
                            Navigator.of(context).pop();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: c.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (imgFile.existsSync())
                                  Image.file(imgFile, fit: BoxFit.cover)
                                else
                                  Container(
                                    color: Colors.black26,
                                    child: const Center(
                                      child: Icon(Icons.image_not_supported_outlined, size: 24, color: Colors.white30),
                                    ),
                                  ),

                                // Timestamp Overlay Bottom
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, Colors.black87],
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Scene #${sc.sceneId}',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        Text(
                                          '${sc.startSec.toStringAsFixed(1)}s - ${sc.endSec.toStringAsFixed(1)}s',
                                          style: const TextStyle(fontSize: 9, color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton.ghost(
                  label: 'Hủy bỏ',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
