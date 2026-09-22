import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/app_colors.dart';
import '../../../../core/python_bridge.dart';
import '../models/movie_review_model.dart';
import 'scene_picker_dialog.dart';

class ReviewStoryboardCard extends StatefulWidget {
  final ScriptSegment segment;
  final String projectName;
  final String videoName;
  final double ttsSpeed;
  final List<SceneMeta> availableScenes;
  final bool isPlayingTts;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<SceneMeta> onAddScene;
  final ValueChanged<int> onRemoveScene;
  final VoidCallback onDeleteSegment;
  final VoidCallback onPreviewTts;
  final VoidCallback onSplitSegment;
  final VoidCallback onMergeWithNext;

  const ReviewStoryboardCard({
    super.key,
    required this.segment,
    required this.projectName,
    required this.videoName,
    required this.ttsSpeed,
    required this.availableScenes,
    this.isPlayingTts = false,
    required this.onTextChanged,
    required this.onAddScene,
    required this.onRemoveScene,
    required this.onDeleteSegment,
    required this.onPreviewTts,
    required this.onSplitSegment,
    required this.onMergeWithNext,
  });

  @override
  State<ReviewStoryboardCard> createState() => _ReviewStoryboardCardState();
}

class _ReviewStoryboardCardState extends State<ReviewStoryboardCard> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.segment.voiceoverText);
  }

  @override
  void didUpdateWidget(covariant ReviewStoryboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment.voiceoverText != widget.segment.voiceoverText &&
        _textController.text != widget.segment.voiceoverText) {
      _textController.text = widget.segment.voiceoverText;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String get _keyframesDirPath {
    final root = PythonBridge.resolveRootDir();
    final safeName = p.withoutExtension(widget.videoName).replaceAll(RegExp(r'[^\w\-]+'), '_');
    return p.join(root, 'resources', widget.projectName, 'workspace', 'movie_review', safeName, 'keyframes');
  }

  Color _getSectionColor(String section) {
    switch (section.toLowerCase()) {
      case 'hook':
        return Colors.orangeAccent;
      case 'review':
        return Colors.purpleAccent;
      case 'outro':
        return AppColors.statusCompleted;
      case 'storytelling':
      default:
        return AppColors.primary;
    }
  }

  String _getSectionLabel(String section) {
    switch (section.toLowerCase()) {
      case 'hook':
        return '🪝 Hook (Mở bài 5%)';
      case 'review':
        return '🔍 Đánh giá (Review 20%)';
      case 'outro':
        return '🎬 Kết luận (Outro 5%)';
      case 'storytelling':
      default:
        return '📖 Kể chuyện (Story 70%)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final sectionColor = _getSectionColor(widget.segment.section);

    final words = widget.segment.voiceoverText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final wpm = 140.0 * widget.ttsSpeed;
    final estSec = wpm > 0 ? (words / wpm) * 60.0 : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                // Tag Phân đoạn
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sectionColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: sectionColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    _getSectionLabel(widget.segment.section),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sectionColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Câu #${widget.segment.id.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),

                // Thống kê số chữ & thời lượng của câu
                Text(
                  '$words chữ (~${estSec.toStringAsFixed(1)}s)',
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
                const SizedBox(width: 12),

                // 1. Nút Nghe thử TTS
                Tooltip(
                  message: widget.isPlayingTts ? 'Dừng phát âm thanh' : 'Nghe thử giọng đọc câu này',
                  child: InkWell(
                    onTap: widget.onPreviewTts,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        widget.isPlayingTts ? Icons.stop_circle : Icons.volume_up_outlined,
                        size: 16,
                        color: widget.isPlayingTts ? Colors.amberAccent : AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 2. Nút Tách phân cảnh
                Tooltip(
                  message: 'Tách phân cảnh (Split câu thoại)',
                  child: InkWell(
                    onTap: widget.onSplitSegment,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.call_split, size: 16, color: c.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 3. Nút Gộp với phân cảnh kế tiếp
                Tooltip(
                  message: 'Gộp với phân cảnh tiếp theo',
                  child: InkWell(
                    onTap: widget.onMergeWithNext,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.merge_type, size: 16, color: c.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 4. Xóa câu thoại
                Tooltip(
                  message: 'Xóa phân cảnh này',
                  child: InkWell(
                    onTap: widget.onDeleteSegment,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Soạn thảo câu thoại (Preserves cursor)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _textController,
              maxLines: null,
              style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Nhập câu thoại voiceover cho phân cảnh này...',
                hintStyle: TextStyle(fontSize: 12, color: c.textMuted),
                filled: true,
                fillColor: c.surfaceLight.withOpacity(0.5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: widget.onTextChanged,
            ),
          ),

          // Dải thumbnail cảnh minh họa (scenes_to_use)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Cảnh ghép minh họa (${widget.segment.scenesToUse.length}):',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textSecondary),
                    ),
                    const Spacer(),
                    // Nút Thêm Cảnh
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => ScenePickerDialog(
                            availableScenes: widget.availableScenes,
                            videoName: widget.videoName,
                            projectName: widget.projectName,
                            onSceneSelected: widget.onAddScene,
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 14, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            '+ Thêm cảnh',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Danh sách ngang các thumbnail cảnh
                if (widget.segment.scenesToUse.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: c.surfaceLight.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.border),
                    ),
                    child: Center(
                      child: Text(
                        'Chưa gán cảnh minh họa. Bấm "+ Thêm cảnh" để chọn từ kho ảnh.',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.segment.scenesToUse.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final sc = widget.segment.scenesToUse[idx];
                        final imgFile = File(p.join(_keyframesDirPath, sc.imagePath));

                        return Container(
                          width: 105,
                          decoration: BoxDecoration(
                            color: c.surfaceLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (imgFile.existsSync())
                                Image.file(imgFile, fit: BoxFit.cover)
                              else
                                const Center(
                                  child: Icon(Icons.movie_outlined, size: 20, color: Colors.white24),
                                ),

                              // Label Scene & Delete button
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  onTap: () => widget.onRemoveScene(sc.sceneId),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),

                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  color: Colors.black87,
                                  child: Text(
                                    '#${sc.sceneId} (${sc.startSec.toStringAsFixed(0)}s)',
                                    style: const TextStyle(fontSize: 9, color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
