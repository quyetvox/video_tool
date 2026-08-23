import 'package:flutter_test/flutter_test.dart';
import 'package:sub_video_desktop/utils/job_id_utils.dart';

void main() {
  group('JobIdUtils Tests', () {
    test('extractStemFromJobId handles various job ID formats', () {
      expect(JobIdUtils.extractStemFromJobId('job_video_001'), 'video_001');
      expect(JobIdUtils.extractStemFromJobId('trans_video_002'), 'video_002');
      expect(JobIdUtils.extractStemFromJobId('resume_video_003'), 'video_003');
      expect(JobIdUtils.extractStemFromJobId('ocr_video_004'), 'video_004');
      expect(JobIdUtils.extractStemFromJobId('batch_sel_video_005'), 'video_005');
      expect(JobIdUtils.extractStemFromJobId('batch_video_006'), 'video_006');
      expect(JobIdUtils.extractStemFromJobId('dl_20260822_120000'), '20260822_120000');
      expect(JobIdUtils.extractStemFromJobId('trim_video_007'), 'video_007');
      expect(JobIdUtils.extractStemFromJobId('cut_video_008'), 'video_008');
      expect(JobIdUtils.extractStemFromJobId('studio_video_009'), 'video_009');
    });

    test('extractStemFromVideoArg handles file paths and job identifiers', () {
      expect(JobIdUtils.extractStemFromVideoArg('assets/foods/src/video_001.mp4'), 'video_001');
      expect(JobIdUtils.extractStemFromVideoArg('assets/foods/output/video_001_vi.mp4'), 'video_001');
      expect(JobIdUtils.extractStemFromVideoArg('foods:job_video_001'), 'video_001');
      expect(JobIdUtils.extractStemFromVideoArg('job_video_001'), 'video_001');
    });
  });
}
