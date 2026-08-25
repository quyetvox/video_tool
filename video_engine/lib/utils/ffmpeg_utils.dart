import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;

class ProbeStream {
  final String codecType;
  final String? codecName;
  final int? width;
  final int? height;
  final double? fps;
  final int? sampleRate;
  final int? channels;

  ProbeStream({
    required this.codecType,
    this.codecName,
    this.width,
    this.height,
    this.fps,
    this.sampleRate,
    this.channels,
  });

  factory ProbeStream.fromJson(Map<String, dynamic> json) {
    double? fps;
    final rFrameRate = json['r_frame_rate'] as String?;
    if (rFrameRate != null && rFrameRate.contains('/')) {
      final parts = rFrameRate.split('/');
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den > 0) {
        fps = num / den;
      }
    }

    return ProbeStream(
      codecType: json['codec_type'] as String? ?? 'unknown',
      codecName: json['codec_name'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      fps: fps,
      sampleRate: json['sample_rate'] != null ? int.tryParse(json['sample_rate'].toString()) : null,
      channels: json['channels'] as int?,
    );
  }
}

class ProbeInfo {
  final double duration;
  final int width;
  final int height;
  final double fps;
  final bool hasAudio;
  final bool hasVideo;
  final List<ProbeStream> streams;
  final Map<String, dynamic> raw;

  ProbeInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasAudio,
    required this.hasVideo,
    required this.streams,
    required this.raw,
  });
}

class FFmpegUtils {
  static String resolveBinary(String binName) {
    // Check standard brew paths on macOS first
    final standardPaths = [
      '/opt/homebrew/bin/$binName',
      '/usr/local/bin/$binName',
      binName,
    ];
    for (final sp in standardPaths) {
      if (File(sp).existsSync()) return sp;
    }
    return binName;
  }

  /// Probes video file metadata using ffprobe JSON output
  static Future<ProbeInfo> probe(String videoPath) async {
    final ffprobeBin = resolveBinary('ffprobe');
    final args = [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      videoPath,
    ];

    final res = await Process.run(ffprobeBin, args);
    if (res.exitCode != 0) {
      throw ProcessException(ffprobeBin, args, 'ffprobe failed: ${res.stderr}', res.exitCode);
    }

    final raw = jsonDecode(res.stdout.toString()) as Map<String, dynamic>;
    final streamsJson = (raw['streams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final streams = streamsJson.map((s) => ProbeStream.fromJson(s)).toList();

    final format = raw['format'] as Map<String, dynamic>? ?? {};
    final duration = double.tryParse(format['duration']?.toString() ?? '0.0') ?? 0.0;

    int width = 0;
    int height = 0;
    double fps = 30.0;
    bool hasAudio = false;
    bool hasVideo = false;

    for (final s in streams) {
      if (s.codecType == 'video') {
        hasVideo = true;
        width = s.width ?? width;
        height = s.height ?? height;
        fps = s.fps ?? fps;
      } else if (s.codecType == 'audio') {
        hasAudio = true;
      }
    }

    return ProbeInfo(
      duration: duration,
      width: width,
      height: height,
      fps: fps,
      hasAudio: hasAudio,
      hasVideo: hasVideo,
      streams: streams,
      raw: raw,
    );
  }

  /// Demuxes input video into separate video and audio streams
  static Future<void> demux({
    required String inputVideo,
    required String outputVideo,
    required String outputAudio,
    double? duration,
  }) async {
    final ffmpegBin = resolveBinary('ffmpeg');

    // 1. Video stream copy
    final videoArgs = ['-y', '-i', inputVideo, '-an', '-c:v', 'copy'];
    if (duration != null && duration > 0) {
      videoArgs.addAll(['-t', duration.toStringAsFixed(2)]);
    }
    videoArgs.add(outputVideo);
    await Process.run(ffmpegBin, videoArgs);

    // 2. Audio stream extract (16-bit PCM WAV, 44.1kHz or 16kHz)
    final audioArgs = [
      '-y', '-i', inputVideo, '-vn',
      '-acodec', 'pcm_s16le',
      '-ar', '44100',
      '-ac', '2',
    ];
    if (duration != null && duration > 0) {
      audioArgs.addAll(['-t', duration.toStringAsFixed(2)]);
    }
    audioArgs.add(outputAudio);
    final audioRes = await Process.run(ffmpegBin, audioArgs);

    // If video has no audio, generate silent audio stream
    if (audioRes.exitCode != 0 || !File(outputAudio).existsSync() || File(outputAudio).lengthSync() < 100) {
      final durStr = (duration != null && duration > 0) ? duration.toStringAsFixed(2) : '5.0';
      final silentArgs = [
        '-y', '-f', 'lavfi',
        '-i', 'anullsrc=r=44100:cl=stereo',
        '-t', durStr,
        '-acodec', 'pcm_s16le',
        outputAudio,
      ];
      await Process.run(ffmpegBin, silentArgs);
    }
  }

  /// Extracts sample frames for OCR / Region detection
  static Future<List<File>> extractFrames({
    required String videoPath,
    required Directory outputDir,
    double startTime = 0.0,
    double duration = 10.0,
    double fps = 1.0,
  }) async {
    outputDir.createSync(recursive: true);
    final ffmpegBin = resolveBinary('ffmpeg');
    final stem = p.basenameWithoutExtension(videoPath);
    final pattern = p.join(outputDir.path, '${stem}_frame_%03d.png');

    final args = [
      '-y',
      '-ss', startTime.toStringAsFixed(2),
      '-i', videoPath,
      '-t', duration.toStringAsFixed(2),
      '-vf', 'fps=$fps',
      pattern,
    ];

    await Process.run(ffmpegBin, args);

    final extracted = outputDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') && p.basename(f.path).startsWith('${stem}_frame_'))
        .toList();
    extracted.sort((a, b) => a.path.compareTo(b.path));
    return extracted;
  }

  /// Gets audio duration in seconds
  static Future<double> getAudioDuration(String audioPath) async {
    final probeInfo = await probe(audioPath);
    return probeInfo.duration;
  }

  /// Mixes multiple audio tracks with volume levels
  static Future<void> mixAudio({
    required String musicPath,
    required String voicePath,
    required String outputPath,
    String? ambientPath,
    String? effectPath,
    String? origVoicePath,
    double? targetDuration,
    double musicVolume = 0.5,
    double ambientVolume = 0.75,
    double voiceVolume = 1.0,
    double origVoiceVolume = 0.05,
  }) async {
    final ffmpegBin = resolveBinary('ffmpeg');
    final inputs = <String>[];
    final filterParts = <String>[];
    int count = 0;

    void addTrack(String? path, double vol) {
      if (path != null && vol > 0.0) {
        final f = File(path);
        if (f.existsSync() && f.lengthSync() > 500) {
          inputs.addAll(['-i', path]);
          filterParts.add('[$count:a]volume=${vol.toStringAsFixed(2)}[v$count]');
          count++;
        }
      }
    }

    addTrack(musicPath, musicVolume);
    addTrack(ambientPath, ambientVolume);
    addTrack(effectPath, 1.0);
    addTrack(origVoicePath, origVoiceVolume);
    addTrack(voicePath, voiceVolume);

    if (count == 0) {
      final dur = (targetDuration != null && targetDuration > 0) ? targetDuration.toStringAsFixed(2) : '1.0';
      await Process.run(ffmpegBin, [
        '-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
        '-t', dur,
        '-c:a', 'pcm_s16le', outputPath,
      ]);
      return;
    }

    if (count == 1) {
      final args = ['-y', ...inputs, '-filter:a', 'volume=1.0'];
      if (targetDuration != null && targetDuration > 0) {
        args.addAll(['-t', targetDuration.toStringAsFixed(2)]);
      }
      args.addAll(['-c:a', 'pcm_s16le', outputPath]);
      await Process.run(ffmpegBin, args);
      return;
    }

    final amixInputs = List.generate(count, (i) => '[v$i]').join();
    String amixFilter = '$amixInputs amix=inputs=$count:duration=longest:dropout_transition=2:normalize=0[aout]';
    String finalMap = '[aout]';

    if (targetDuration != null && targetDuration > 0) {
      amixFilter += ';[aout]apad=whole_dur=${targetDuration.toStringAsFixed(2)}[afinal]';
      finalMap = '[afinal]';
    }

    final filterComplex = '${filterParts.join(';')};$amixFilter';
    final args = ['-y', ...inputs, '-filter_complex', filterComplex, '-map', finalMap];
    if (targetDuration != null && targetDuration > 0) {
      args.addAll(['-t', targetDuration.toStringAsFixed(2)]);
    }
    args.addAll(['-c:a', 'pcm_s16le', outputPath]);

    final res = await Process.run(ffmpegBin, args);
    if (res.exitCode != 0) {
      throw ProcessException(ffmpegBin, args, 'Audio mix failed: ${res.stderr}', res.exitCode);
    }
  }

  /// Final encoding into compatible MP4 container
  static Future<void> encodeFinal({
    required String videoIn,
    required String audioIn,
    required String outputFile,
    String bitrate = '4.0M',
  }) async {
    final ffmpegBin = resolveBinary('ffmpeg');
    final probeInfo = await probe(videoIn);
    final videoCodec = probeInfo.streams.where((s) => s.codecType == 'video').map((s) => s.codecName).firstOrNull;

    // 1. If already H.264, use fast stream copy (~0.1s)
    if (videoCodec == 'h264' || videoCodec == 'avc1') {
      final copyArgs = [
        '-y',
        '-i', videoIn,
        '-i', audioIn,
        '-c:v', 'copy',
        '-c:a', 'aac',
        '-map', '0:v:0',
        '-map', '1:a:0',
        '-shortest',
        outputFile,
      ];
      final resCopy = await Process.run(ffmpegBin, copyArgs);
      if (resCopy.exitCode == 0 && File(outputFile).existsSync() && File(outputFile).lengthSync() > 1000) {
        return;
      }
    }

    // 2. Hardware acceleration with Apple VideoToolbox first on macOS
    if (Platform.isMacOS) {
      final hwArgs = [
        '-y',
        '-i', videoIn,
        '-i', audioIn,
        '-c:v', 'h264_videotoolbox',
        '-b:v', bitrate,
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-map', '0:v:0',
        '-map', '1:a:0',
        '-shortest',
        outputFile,
      ];
      final resHw = await Process.run(ffmpegBin, hwArgs);
      if (resHw.exitCode == 0 && File(outputFile).existsSync() && File(outputFile).lengthSync() > 1000) {
        return;
      }
    }

    // 3. Fallback to CPU libx264
    final swArgs = [
      '-y',
      '-i', videoIn,
      '-i', audioIn,
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-b:v', bitrate,
      '-pix_fmt', 'yuv420p',
      '-c:a', 'aac',
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-shortest',
      outputFile,
    ];
    final resSw = await Process.run(ffmpegBin, swArgs);
    if (resSw.exitCode != 0) {
      throw ProcessException(ffmpegBin, swArgs, 'Final encode failed: ${resSw.stderr}', resSw.exitCode);
    }
  }

  /// Applies watermark (text or image) with optional background blur and opacity
  static Future<bool> applyWatermark({
    required String inputVideo,
    required String outputVideo,
    required Map<String, dynamic> config,
    int? width,
    int? height,
  }) async {
    final wmCfg = config['watermark'] is Map ? config['watermark'] as Map : {};
    final enabled = (config['watermark_enabled'] ?? config['watermark_enable'] ?? wmCfg['enabled'] ?? wmCfg['enable'] ?? false) == true;
    final text = (config['watermark_text'] ?? wmCfg['text'] ?? '').toString().trim();
    final image = (config['watermark_image'] ?? wmCfg['image'] ?? '').toString().trim();

    if (!enabled || (text.isEmpty && image.isEmpty)) {
      return false;
    }

    final ffmpegBin = resolveBinary('ffmpeg');
    final probeInfo = (width == null || height == null) ? await probe(inputVideo) : null;
    final w = width ?? probeInfo?.width ?? 1080;
    final h = height ?? probeInfo?.height ?? 1920;

    List<double> region = [0.01, 0.56, 0.06, 1.00];
    final cfgRegion = config['watermark_region'] ?? wmCfg['region'];
    if (cfgRegion is List && cfgRegion.length == 4) {
      region = cfgRegion.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    }

    final topPx = (region[0] * h).round();
    final leftPx = (region[1] * w).round();
    final bottomPx = (region[2] * h).round();
    final rightPx = (region[3] * w).round();
    final boxW = rightPx - leftPx;
    final boxH = bottomPx - topPx;

    final fontName = (config['watermark_font_name'] ?? wmCfg['font_name'] ?? 'Arial').toString().trim();
    final fontColor = (config['watermark_font_color'] ?? wmCfg['font_color'] ?? 'white').toString();
    final opacity = double.tryParse((config['watermark_opacity'] ?? wmCfg['opacity'])?.toString() ?? '0.8') ?? 0.8;
    final blurBg = (config['watermark_blur_bg'] ?? wmCfg['blur_bg'] ?? false) == true;

    final filters = <String>[];
    String lastStream = '[0:v]';

    if (blurBg) {
      filters.add('$lastStream split[wm_m][wm_tb];[wm_tb]crop=$boxW:$boxH:$leftPx:$topPx,avgblur=5[wm_bl];[wm_m][wm_bl]overlay=$leftPx:$topPx[v_wm_bg]');
      lastStream = '[v_wm_bg]';
    }

    if (text.isNotEmpty) {
      final fontSize = max(14, (boxH * 0.60).round());
      final safeText = text.replaceAll("'", "\\'").replaceAll(":", "\\:");
      final customFontsDir = (config['subtitle_fonts_dir'] ?? config['fonts_dir'] ?? (config['subtitle'] is Map ? (config['subtitle'] as Map)['fonts_dir'] : null))?.toString();
      final fontFilePath = _resolveSystemFontFile(fontName, customFontsDir: customFontsDir);
      final fontParam = (fontFilePath != null && File(fontFilePath).existsSync())
          ? "fontfile='$fontFilePath'"
          : "font='$fontName'";

      final posX = "max(4, min(w-text_w-4, $leftPx+(($boxW-text_w)/2)))";
      final posY = "max(4, min(h-text_h-4, $topPx+(($boxH-text_h)/2)))";
      final drawText = "drawtext=text='$safeText':$fontParam:fontsize=$fontSize:fontcolor=$fontColor@$opacity:shadowcolor=black@0.6:shadowx=2:shadowy=2:x='$posX':y='$posY'";
      filters.add('$lastStream $drawText[vfinal]');
      lastStream = '[vfinal]';
    }

    final args = [
      '-y',
      '-i', inputVideo,
      '-filter_complex', filters.join(';'),
      '-map', lastStream,
      '-c:v', 'h264_videotoolbox',
      '-b:v', config['video_bitrate']?.toString() ?? '4.0M',
      '-pix_fmt', 'yuv420p',
      '-an',
      outputVideo,
    ];

    final res = await Process.run(ffmpegBin, args);
    return res.exitCode == 0 && File(outputVideo).existsSync() && File(outputVideo).lengthSync() > 1000;
  }

  static String? _resolveSystemFontFile(String fontName, {String? customFontsDir}) {
    final clean = fontName.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
    final fontDirs = <String>[];

    if (customFontsDir != null && customFontsDir.trim().isNotEmpty) {
      fontDirs.add(customFontsDir.trim());
    }

    fontDirs.addAll([
      p.join(Directory.current.path, 'assets', 'fonts'),
      p.join(Directory.current.path, '..', 'assets', 'fonts'),
      '/System/Library/Fonts/Supplemental',
      '/Library/Fonts',
      '/System/Library/Fonts',
    ]);

    for (final dirPath in fontDirs) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        try {
          for (final entity in dir.listSync()) {
            if (entity is File && (entity.path.endsWith('.ttf') || entity.path.endsWith('.otf') || entity.path.endsWith('.ttc'))) {
              final stem = p.basenameWithoutExtension(entity.path).toLowerCase().replaceAll(' ', '').replaceAll('-', '');
              if (stem == clean || stem.startsWith(clean) || clean.startsWith(stem)) {
                return entity.path;
              }
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }
}
