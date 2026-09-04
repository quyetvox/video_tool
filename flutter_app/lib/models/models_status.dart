class ModelsStatus {
  final String modelsDir;
  final String venvPath;
  final bool pythonFound;
  final bool whisperFound;
  final bool demucsFound;
  final bool paddleOcrFound;

  const ModelsStatus({
    this.modelsDir = '',
    required this.venvPath,
    required this.pythonFound,
    required this.whisperFound,
    required this.demucsFound,
    required this.paddleOcrFound,
  });

  bool get allReady => pythonFound && whisperFound && demucsFound;

  factory ModelsStatus.empty() => const ModelsStatus(
        modelsDir: '',
        venvPath: '',
        pythonFound: false,
        whisperFound: false,
        demucsFound: false,
        paddleOcrFound: false,
      );

  factory ModelsStatus.fromJson(Map<String, dynamic> json) {
    return ModelsStatus(
      modelsDir: json['models_dir'] as String? ?? '',
      venvPath: json['venv_path'] as String? ?? '',
      pythonFound: json['python_found'] as bool? ?? false,
      whisperFound: json['whisper_found'] as bool? ?? false,
      demucsFound: json['demucs_found'] as bool? ?? false,
      paddleOcrFound: json['paddleocr_found'] as bool? ?? false,
    );
  }
}
