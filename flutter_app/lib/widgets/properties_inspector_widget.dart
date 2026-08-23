import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  double _previewVolume = 1.0;
  bool _isMuted = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
      ),
      child: Column(
        children: [
          // Header Subtabs
          Container(
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF0B1120),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
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
    final isActive = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFF06B6D4) : Colors.transparent,
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
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesTab() {
    if (widget.videoFile == null) {
      return const Center(
        child: Text('Chưa chọn video nào', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
      );
    }

    final video = widget.videoFile!;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('THÔNG TIN VIDEO (BASIC INFO)', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        _buildInfoRow('Tên File', video.basename),
        _buildInfoRow('Độ Phân Giải', '1920x1080 (HD 1080p)'),
        _buildInfoRow('Tốc Độ Khung Hình', '30 fps'),
        _buildInfoRow('Thời Lượng', TimeFormatUtils.formatDuration(widget.duration)),
        _buildInfoRow('Dung Lượng', TimeFormatUtils.formatFileSize(video.sizeBytes)),

        const Divider(color: Color(0xFF1E293B), height: 20),

        // Quick Audio Volume & Mute
        const Text('ÂM LƯỢNG PHÁT THỬ', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, size: 16, color: const Color(0xFF10B981)),
              onPressed: () => setState(() => _isMuted = !_isMuted),
            ),
            Expanded(
              child: Slider(
                value: _isMuted ? 0.0 : _previewVolume,
                min: 0.0,
                max: 1.0,
                onChanged: (v) {
                  setState(() {
                    _previewVolume = v;
                    _isMuted = v == 0;
                  });
                },
              ),
            ),
            Text('${((_isMuted ? 0.0 : _previewVolume) * 100).toInt()}%', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11)),
          ],
        ),

        const Divider(color: Color(0xFF1E293B), height: 20),

        // Trim Specs & Overwrite Cut
        const Text('CẮT BỎ ĐOẠN RÁC (MS ACCURATE)', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildInfoRow('Điểm Bắt Đầu', TimeFormatUtils.formatSubtitleTime(widget.startTime)),
        _buildInfoRow('Điểm Kết Thúc', TimeFormatUtils.formatSubtitleTime(widget.endTime)),
        _buildInfoRow('Thời Lượng Cắt', '${(widget.endTime - widget.startTime).toStringAsFixed(2)}s'),
        _buildInfoRow('Chế Độ', widget.cutMode == 'remove' ? 'Loại Bỏ Rác' : 'Trimmer'),

        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            minimumSize: const Size(0, 28),
          ),
          icon: widget.isProcessing
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_sweep, size: 14),
          label: const Text('Loại Bỏ Đoạn Rác (Ghi Đè)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          onPressed: widget.isProcessing ? null : widget.onCutTrim,
        ),
      ],
    );
  }

  Widget _buildStepsTab() {
    if (widget.activeProject == null || widget.videoFile == null) {
      return const Center(child: Text('Chọn video để xem steps', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)));
    }

    return StepProgressIndicator(
      project: widget.activeProject,
      jobId: widget.videoFile!.jobId,
      projectsDir: widget.projectsDir,
    );
  }

  Widget _buildMetadataTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('AI GENERATED METADATA', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        // Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Tiêu Đề Video (Title):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            if (widget.metaTitle.isNotEmpty)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.metaTitle));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép tiêu đề!')));
                },
                child: const Text('Sao chép', style: TextStyle(fontSize: 10.5, color: Color(0xFF06B6D4))),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(4)),
          child: Text(widget.metaTitle.isNotEmpty ? widget.metaTitle : 'Chưa sinh metadata', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),

        const SizedBox(height: 10),

        // Description
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Mô Tả Video (Description):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            if (widget.metaDesc.isNotEmpty)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.metaDesc));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép mô tả!')));
                },
                child: const Text('Sao chép', style: TextStyle(fontSize: 10.5, color: Color(0xFF06B6D4))),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(4)),
          child: Text(widget.metaDesc.isNotEmpty ? widget.metaDesc : 'Chưa có mô tả', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),

        const SizedBox(height: 10),

        // Hashtags
        const Text('Hashtags Xu Hướng:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: widget.metaHashtags.map((tag) => Chip(
            label: Text(tag, style: const TextStyle(fontSize: 10.5)),
            backgroundColor: const Color(0xFF1E293B),
          )).toList(),
        ),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            minimumSize: const Size(0, 28),
          ),
          icon: const Icon(Icons.copy, size: 14),
          label: const Text('📋 Sao Chép Toàn Bộ Metadata', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
