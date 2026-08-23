import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers.dart';
import '../core/python_bridge.dart';
import '../models/video_file.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/multitrack_timeline_widget.dart';
import '../utils/time_format_utils.dart';

class VideoStudioScreen extends ConsumerStatefulWidget {
  const VideoStudioScreen({super.key});

  @override
  ConsumerState<VideoStudioScreen> createState() => _VideoStudioScreenState();
}

class _VideoStudioScreenState extends ConsumerState<VideoStudioScreen> {
  double _currentTime = 0.0;
  double _duration = 100.0;

  // Junk Cut state
  double _junkStart = 5.0;
  double _junkEnd = 15.0;
  final List<Map<String, double>> _junkRanges = [
    {'start': 5.0, 'end': 15.0}
  ];

  // Export settings
  final String _exportFilename = 'dedup_report_clean.mp4';
  String _exportResolution = 'Giữ nguyên (1920x1080)';
  String _exportFps = '30 fps';
  String _exportRatio = '16:9 (Ngang)';
  String _exportBitrate = 'Cao (4.0M HD Sắc Nét)';

  // Live Mixer Audio Volumes
  double _volVideo = 1.0;
  double _volMusic = 0.8;
  double _volFx = 0.6;

  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final selectedVideo = ref.watch(selectedVideoProvider);
    final projectVideosAsync = ref.watch(projectVideosProvider);
    final projectVideos = projectVideosAsync.value ?? {
      'srcFiles': <VideoFile>[],
      'cutFiles': <VideoFile>[],
      'mergeFiles': <VideoFile>[],
      'outputFiles': <VideoFile>[],
    };

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Column(
        children: [
          // 1. Top Studio Subheader
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Text(
                  'Video Studio  ›  Video Editor  ›  Cắt bỏ đoạn rác',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8B5CF6),
                    side: const BorderSide(color: Color(0xFF8B5CF6)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.video_collection, size: 13),
                  label: Text(
                    selectedVideo != null ? selectedVideo.basename : 'Chọn video',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _showVideoSelectorDialog(projectVideos),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.save_outlined, size: 14),
                  label: const Text('Lưu nháp', style: TextStyle(fontSize: 11)),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  icon: _isProcessing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.content_cut, size: 14),
                  label: const Text('✂️ Cắt bỏ & Xuất', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: selectedVideo == null || _isProcessing ? null : () => _executeCutAndExport(selectedVideo),
                ),
              ],
            ),
          ),

          // 2. Upper 3-Column Workspace (Player, Junk Picker, Export Specs)
          Expanded(
            flex: 55,
            child: Row(
              children: [
                // Column 1: Video Player (40%)
                Expanded(
                  flex: 40,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      border: Border(
                        right: BorderSide(color: Color(0xFF1E293B)),
                        bottom: BorderSide(color: Color(0xFF1E293B)),
                      ),
                    ),
                    child: selectedVideo != null
                        ? VideoPlayerWidget(
                            videoPath: selectedVideo.fullPath,
                            onPositionChanged: (sec) => setState(() => _currentTime = sec),
                            onDurationChanged: (dur) => setState(() => _duration = dur),
                          )
                        : const Center(
                            child: Text('Chưa có video nào được chọn', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          ),
                  ),
                ),

                // Column 2: Junk Selection Panel (35%)
                Expanded(
                  flex: 35,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      border: Border(
                        right: BorderSide(color: Color(0xFF1E293B)),
                        bottom: BorderSide(color: Color(0xFF1E293B)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Khung chọn đoạn rác (Mặc định 10s):', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: const Color(0xFF06B6D4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              icon: const Icon(Icons.location_on, size: 12),
                              label: const Text('Đặt 10s tại Playhead', style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                setState(() {
                                  _junkStart = _currentTime;
                                  _junkEnd = (_currentTime + 10.0).clamp(0.0, _duration);
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: const Color(0xFF06B6D4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              icon: const Icon(Icons.timer, size: 12),
                              label: const Text('10s đầu', style: TextStyle(fontSize: 11)),
                              onPressed: () {
                                setState(() {
                                  _junkStart = 0.0;
                                  _junkEnd = 10.0.clamp(0.0, _duration);
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Bắt đầu:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF334155))),
                                    child: Text(TimeFormatUtils.formatSubtitleTime(_junkStart), style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Kết thúc:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF334155))),
                                    child: Text(TimeFormatUtils.formatSubtitleTime(_junkEnd), style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF06B6D4),
                            side: const BorderSide(color: Color(0xFF06B6D4)),
                            minimumSize: const Size(double.infinity, 34),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('+ Thêm đoạn rác này vào danh sách', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setState(() {
                              _junkRanges.add({'start': _junkStart, 'end': _junkEnd});
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Text('Danh sách đoạn rác cần cắt bỏ (${_junkRanges.length})', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _junkRanges.length,
                            itemBuilder: (ctx, idx) {
                              final item = _junkRanges[idx];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(4)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.content_cut, size: 12, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${TimeFormatUtils.formatSubtitleTime(item['start']!)} ➔ ${TimeFormatUtils.formatSubtitleTime(item['end']!)}',
                                      style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 11),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                                      onPressed: () => setState(() => _junkRanges.removeAt(idx)),
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
                ),

                // Column 3: History & Export Specs (25%)
                Expanded(
                  flex: 25,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
                    ),
                    child: ListView(
                      children: [
                        const Text('Thuộc tính xuất video', style: TextStyle(color: Color(0xFF06B6D4), fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Tên file xuất:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: const Color(0xFF0B1120), borderRadius: BorderRadius.circular(4)),
                          child: Text(_exportFilename, style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 11)),
                        ),
                        const SizedBox(height: 10),
                        const Text('Độ phân giải:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        DropdownButton<String>(
                          value: _exportResolution,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: ['Giữ nguyên (1920x1080)', '1080x1920 (Dọc 9:16)', '1280x720'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setState(() => _exportResolution = v!),
                        ),
                        const SizedBox(height: 10),
                        const Text('Tỉ lệ khung hình:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        DropdownButton<String>(
                          value: _exportRatio,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: ['16:9 (Ngang)', '9:16 (Dọc TikTok)', '1:1 (Vuông)'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setState(() => _exportRatio = v!),
                        ),
                        const SizedBox(height: 10),
                        const Text('Khung hình (FPS):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        DropdownButton<String>(
                          value: _exportFps,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: ['30 fps', '60 fps', '24 fps'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setState(() => _exportFps = v!),
                        ),
                        const SizedBox(height: 10),
                        const Text('Chất lượng (Bitrate):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        DropdownButton<String>(
                          value: _exportBitrate,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: ['Cao (4.0M HD Sắc Nét)', 'Trung bình (2.5M)', 'Tiết kiệm (1.5M)'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setState(() => _exportBitrate = v!),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Bottom Multitrack Timeline
          Expanded(
            flex: 35,
            child: MultitrackTimelineWidget(
              duration: _duration,
              currentTime: _currentTime,
              junkStart: _junkStart,
              junkEnd: _junkEnd,
              onSeek: (sec) => setState(() => _currentTime = sec),
            ),
          ),

          // 4. Audio Mixer Footer Bar
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const Text('MIXER ÂM THANH:', style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                _buildMixerSlider('Video', _volVideo, (v) => setState(() => _volVideo = v)),
                const SizedBox(width: 16),
                _buildMixerSlider('Nhạc nền', _volMusic, (v) => setState(() => _volMusic = v)),
                const SizedBox(width: 16),
                _buildMixerSlider('Hiệu ứng', _volFx, (v) => setState(() => _volFx = v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMixerSlider(String label, double value, Function(double) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        SizedBox(
          width: 80,
          child: Slider(value: value, min: 0.0, max: 1.0, onChanged: onChanged),
        ),
        Text('${(value * 100).toInt()}%', style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 10.5)),
      ],
    );
  }

  void _showVideoSelectorDialog(Map<String, List<VideoFile>> videos) {
    final all = [
      ...videos['srcFiles'] ?? [],
      ...videos['cutFiles'] ?? [],
      ...videos['mergeFiles'] ?? [],
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Chọn Video Để Biên Tập', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: all.length,
            itemBuilder: (c, idx) {
              final vid = all[idx];
              return ListTile(
                dense: true,
                title: Text(vid.basename, style: const TextStyle(color: Colors.white, fontSize: 12)),
                subtitle: Text('${vid.category.name.toUpperCase()} • ${TimeFormatUtils.formatFileSize(vid.sizeBytes)}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
                onTap: () {
                  ref.read(selectedVideoProvider.notifier).state = vid;
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _executeCutAndExport(VideoFile video) async {
    setState(() => _isProcessing = true);
    final removeArgs = _junkRanges.map((r) {
      final s = TimeFormatUtils.formatSubtitleTime(r['start']!).replaceAll(',', '.');
      final e = TimeFormatUtils.formatSubtitleTime(r['end']!).replaceAll(',', '.');
      return '$s-$e';
    }).toList();

    final args = [
      video.fullPath,
      '--remove',
      ...removeArgs,
      '--overwrite',
    ];

    final res = await PythonBridge.runScript('concat.py', args, jobId: 'studio_cut_${video.stem}');
    setState(() => _isProcessing = false);

    if (res.success) {
      ref.invalidate(projectVideosProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cắt bỏ đoạn rác và xuất video hoàn tất!')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: ${res.output}')));
      }
    }
  }
}
