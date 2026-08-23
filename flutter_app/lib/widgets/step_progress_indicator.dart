import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/file_service.dart';

const List<Map<String, String>> pipelineSteps = [
  {'id': 's01_probe', 'label': '1. Probe Video', 'desc': 'Phân tích kích thước, fps, duration'},
  {'id': 's02_demux', 'label': '2. Demux Streams', 'desc': 'Tách luồng video & audio gốc'},
  {'id': 's03_subtitle_detect', 'label': '3. Subtitle Detect', 'desc': 'Nhận diện vùng sub cũ'},
  {'id': 's04_audio_separate', 'label': '4. Demucs Separate', 'desc': 'Tách giọng nói & nhạc nền bằng AI'},
  {'id': 's05_asr', 'label': '5. Whisper ASR', 'desc': 'Nhận diện giọng nói thành văn bản'},
  {'id': 's05b_gender_detect', 'label': '5b. Gender Detect', 'desc': 'Phân tích tần số giọng Nam/Nữ'},
  {'id': 's06_ocr', 'label': '6. PaddleOCR', 'desc': 'Nhận diện chữ sub cứng bằng OCR'},
  {'id': 's07_transcript_merge', 'label': '7. Transcript Fusion', 'desc': 'Gộp ASR và OCR'},
  {'id': 's08_translation', 'label': '8. Translation', 'desc': 'Dịch câu thoại sang tiếng Việt'},
  {'id': 's08b_metadata_gen', 'label': '8b. Metadata AI', 'desc': 'Tự động sinh tiêu đề & hashtags'},
  {'id': 's08c_timing', 'label': '8c. Sub Timing', 'desc': 'Tối ưu nhịp đọc subtitle'},
  {'id': 's09_subtitle_gen', 'label': '9. Subtitle Gen', 'desc': 'Tạo file phụ đề ASS và SubBox'},
  {'id': 's10_inpaint', 'label': '10. Inpaint & Blur', 'desc': 'Xóa sub cũ & đóng watermark'},
  {'id': 's11_subtitle_render', 'label': '11. Sub Render', 'desc': 'Ghép sub mới vào video'},
  {'id': 's12_tts', 'label': '12. EdgeTTS Voice', 'desc': 'Đọc thuyết minh tiếng Việt'},
  {'id': 's13_audio_mix', 'label': '13. Audio Mix', 'desc': 'Trộn nhạc nền + voice + effect'},
  {'id': 's14_encode', 'label': '14. Final Encode', 'desc': 'Xuất video H.264/AAC ra output/'},
];

class StepProgressIndicator extends StatelessWidget {
  final Set<String>? completedSteps;
  final String? currentRunningStep;
  final Function(String stepId)? onDeleteStepCache;
  final String? project;
  final String? jobId;
  final String? projectsDir;

  const StepProgressIndicator({
    super.key,
    this.completedSteps,
    this.currentRunningStep,
    this.onDeleteStepCache,
    this.project,
    this.jobId,
    this.projectsDir,
  });

  Set<String> _resolveCompletedSteps() {
    if (completedSteps != null) return completedSteps!;
    final set = <String>{};
    if (project == null || jobId == null || projectsDir == null) return set;

    final jobDir = Directory(p.join(projectsDir!, project!, 'workspace', jobId!));
    if (!jobDir.existsSync()) return set;

    try {
      final files = jobDir.listSync(recursive: true).whereType<File>().map((f) => p.basename(f.path)).toList();
      for (final f in files) {
        if (f.contains('s01') || f.contains('probe')) set.add('s01_probe');
        if (f.contains('s02') || f.contains('video_stream')) set.add('s02_demux');
        if (f.contains('s03')) set.add('s03_subtitle_detect');
        if (f.contains('s04') || f.contains('voice.wav')) set.add('s04_audio_separate');
        if (f.contains('s05_asr')) set.add('s05_asr');
        if (f.contains('s05b')) set.add('s05b_gender_detect');
        if (f.contains('s06_ocr')) set.add('s06_ocr');
        if (f.contains('s07_transcript')) set.add('s07_transcript_merge');
        if (f.contains('s08_translation')) set.add('s08_translation');
        if (f.contains('s08b_metadata')) set.add('s08b_metadata_gen');
        if (f.contains('s08c_timing')) set.add('s08c_timing');
        if (f.contains('s09') || f.endsWith('.ass') || f.endsWith('.srt')) set.add('s09_subtitle_gen');
        if (f.contains('s10') || f.contains('clean_video')) set.add('s10_inpaint');
        if (f.contains('s11') || f.contains('rendered_video')) set.add('s11_subtitle_render');
        if (f.contains('s12') || f.contains('tts_audio')) set.add('s12_tts');
        if (f.contains('s13') || f.contains('mixed_audio')) set.add('s13_audio_mix');
        if (f.contains('s14')) set.add('s14_encode');
      }
    } catch (_) {}

    return set;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSteps = _resolveCompletedSteps();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 15, color: Color(0xFF06B6D4)),
              const SizedBox(width: 8),
              const Text(
                'Tiến trình 15 bước',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
              ),
              const Spacer(),
              Text(
                '${effectiveSteps.length}/${pipelineSteps.length} xong',
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: pipelineSteps.length,
              itemBuilder: (ctx, idx) {
                final step = pipelineSteps[idx];
                final stepId = step['id']!;
                final isCompleted = effectiveSteps.contains(stepId);
                final isRunning = currentRunningStep == stepId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1120),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isCompleted ? const Color(0xFF10B981).withOpacity(0.3) : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCompleted ? Icons.check_circle : (isRunning ? Icons.sync : Icons.radio_button_unchecked),
                        size: 14,
                        color: isCompleted ? const Color(0xFF10B981) : (isRunning ? const Color(0xFF06B6D4) : const Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step['label']!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                                color: isCompleted ? Colors.white : const Color(0xFF94A3B8),
                              ),
                            ),
                            Text(step['desc']!, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B))),
                          ],
                        ),
                      ),
                      if (isCompleted && (onDeleteStepCache != null || (project != null && jobId != null && projectsDir != null)))
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 13, color: Color(0xFFEF4444)),
                          tooltip: 'Xóa cache bước này',
                          onPressed: () {
                            if (onDeleteStepCache != null) {
                              onDeleteStepCache!(stepId);
                            } else if (project != null && jobId != null && projectsDir != null) {
                              FileService.deleteStepCache(projectsDir!, project!, jobId!, stepId);
                            }
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
