import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../models/video_file.dart';
import '../utils/time_format_utils.dart';
import 'step_progress_indicator.dart';

class PropertiesInspectorWidget extends StatefulWidget {
  final VideoFile? videoFile;
  final double duration;
  final double startTime;
  final double endTime;
  final String cutMode;
  final VoidCallback onCutTrim;
  final String? activeProject;
  final String projectsDir;
  final String metaTitle;
  final String metaDesc;
  final List<String> metaHashtags;
  final bool isProcessing;

  const PropertiesInspectorWidget({
    super.key,
    required this.videoFile,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.cutMode,
    required this.onCutTrim,
    this.activeProject,
    required this.projectsDir,
    this.metaTitle = '',
    this.metaDesc = '',
    this.metaHashtags = const [],
    this.isProcessing = false,
  });

  @override
  State<PropertiesInspectorWidget> createState() => _PropertiesInspectorWidgetState();
}

class _PropertiesInspectorWidgetState extends State<PropertiesInspectorWidget> {
  int _activeTab = 0; // 0: Properties, 1: Steps, 2: AI Metadata

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
      ),
      child: Column(
        children: [
          // Header Subtabs
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: c.surfaceDark,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                _buildTabBtn(title: 'Properties', index: 0),
                _buildTabBtn(title: 'Steps (15)', index: 1),
                _buildTabBtn(title: 'AI Metadata', index: 2),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _activeTab == 0
                ? _buildPropertiesTab()
                : _activeTab == 1
                    ? _buildStepsTab()
                    : _buildMetadataTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBtn({required String title, required int index}) {
    final c = AppColors.of(context);
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? c.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? c.primary : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesTab() {
    final c = AppColors.of(context);
    if (widget.videoFile == null) {
      return Center(
        child: Text('Chưa chọn video nào', style: TextStyle(color: c.textMuted, fontSize: 11)),
      );
    }

    final video = widget.videoFile!;

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text('THÔNG TIN VIDEO (BASIC INFO)', style: TextStyle(color: c.primary, fontSize: 10.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),

        _buildInfoRow('Tên File', video.basename),
        _buildInfoRow('Độ Phân Giải', '1920x1080 (HD 1080p)'),
        _buildInfoRow('Tốc Độ Khung Hình', '30 fps'),
        _buildInfoRow('Thời Lượng', TimeFormatUtils.formatDuration(widget.duration)),
        _buildInfoRow('Dung Lượng', TimeFormatUtils.formatFileSize(video.sizeBytes)),

        Divider(color: c.border, height: 16),

        // Quick Audio Volume & Mute
        // Text('ÂM LƯỢNG PHÁT THỬ', style: TextStyle(color: c.statusCompleted, fontSize: 10.5, fontWeight: FontWeight.w600)),
        // const SizedBox(height: 4),
        // Row(
        //   children: [
        //     IconButton(
        //       icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, size: 15, color: c.statusCompleted),
        //       onPressed: () => setState(() => _isMuted = !_isMuted),
        //     ),
        //     Expanded(
        //       child: Slider(
        //         value: _isMuted ? 0.0 : _previewVolume,
        //         min: 0.0,
        //         max: 1.0,
        //         activeColor: c.primary,
        //         onChanged: (v) {
        //           setState(() {
        //             _previewVolume = v;
        //             _isMuted = v == 0;
        //           });
        //         },
        //       ),
        //     ),
        //     Text('${((_isMuted ? 0.0 : _previewVolume) * 100).toInt()}%', style: TextStyle(color: c.statusCompleted, fontSize: 10.5)),
        //   ],
        // ),
      ],
    );
  }

  Widget _buildStepsTab() {
    final c = AppColors.of(context);
    if (widget.activeProject == null || widget.videoFile == null) {
      return Center(child: Text('Chọn video để xem steps', style: TextStyle(color: c.textMuted, fontSize: 11)));
    }

    return StepProgressIndicator(
      project: widget.activeProject,
      jobId: widget.videoFile!.jobId,
      projectsDir: widget.projectsDir,
    );
  }

  Widget _buildMetadataTab() {
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text('AI GENERATED METADATA', style: TextStyle(color: c.primary, fontSize: 10.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),

        // Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tiêu Đề Video (Title):', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
            if (widget.metaTitle.isNotEmpty)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.metaTitle));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép tiêu đề!')));
                },
                child: Text('Sao chép', style: TextStyle(fontSize: 10, color: c.primary)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(4), border: Border.all(color: c.border, width: 0.6)),
          child: Text(widget.metaTitle.isNotEmpty ? widget.metaTitle : 'Chưa sinh metadata', style: TextStyle(color: c.textPrimary, fontSize: 11)),
        ),

        const SizedBox(height: 8),

        // Description
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mô Tả Video (Description):', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
            if (widget.metaDesc.isNotEmpty)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.metaDesc));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép mô tả!')));
                },
                child: Text('Sao chép', style: TextStyle(fontSize: 10, color: c.primary)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: c.surfaceDark, borderRadius: BorderRadius.circular(4), border: Border.all(color: c.border, width: 0.6)),
          child: Text(widget.metaDesc.isNotEmpty ? widget.metaDesc : 'Chưa có mô tả', style: TextStyle(color: c.textPrimary, fontSize: 11)),
        ),

        const SizedBox(height: 8),

        // Hashtags
        Text('Hashtags Xu Hướng:', style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 5,
          children: widget.metaHashtags.map((tag) => Chip(
            label: Text(tag, style: TextStyle(fontSize: 10, color: c.primary)),
            backgroundColor: c.surfaceLight,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )).toList(),
        ),

        const SizedBox(height: 12),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: c.primaryText,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            minimumSize: const Size(0, 26),
          ),
          icon: const Icon(Icons.copy, size: 13),
          label: const Text('📋 Sao Chép Toàn Bộ Metadata', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
          onPressed: () {
            final all = '${widget.metaTitle}\n\n${widget.metaDesc}\n\n${widget.metaHashtags.join(" ")}';
            Clipboard.setData(ClipboardData(text: all));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép toàn bộ metadata vào clipboard!')));
          },
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: c.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
