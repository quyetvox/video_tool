class JobIdUtils {
  static final RegExp _prefixRegex = RegExp(
    r'^(job_|trans_|resume_|ocr_|batch_sel_|batch_|dl_|trim_|cut_|studio_|sync_down_|sync_up_|offload_|del_cloud_)',
  );

  static final RegExp _videoExtRegex = RegExp(r'(_vi\.[^/.]+$|\.[^/.]+$)');

  /// Extract clean stem from jobId
  static String extractStemFromJobId(String jobId) {
    if (jobId.isEmpty) return '';
    return jobId.replaceAll(_prefixRegex, '');
  }

  /// Extract clean stem from video argument (e.g. assets/foods/src/video_001.mp4 or foods:job_video_001)
  static String extractStemFromVideoArg(String videoArg) {
    if (videoArg.isEmpty) return '';
    final lastPart = videoArg.split('/').last.split(':').last;
    final withoutPrefix = lastPart.replaceAll(RegExp(r'^job_'), '');
    return withoutPrefix.replaceAll(_videoExtRegex, '');
  }
}
