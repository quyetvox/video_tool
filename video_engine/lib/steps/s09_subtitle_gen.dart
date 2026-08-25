import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../utils/ass_utils.dart';
import '../core/job_state.dart';
import '../core/step_base.dart';

class StepSubtitleGen extends StepBase {
  @override
  String get stepId => 's09_subtitle_gen';

  @override
  List<String> get dependsOn => const ['s08_translation', 's08c_timing'];

  @override
  List<String> get stepConfigKeys => const [
        'show_subtitle',
        'subtitle',
        'subtitle_font_name',
        'subtitle_font_size',
        'subtitle_font_color',
        'subtitle_outline_color',
        'subtitle_secondary_font_name',
        'subtitle_secondary_font_size_scale',
        'subtitle_secondary_font_color',
        'subtitle_secondary_outline_color',
        'subtitle_order',
        'subtitle_box_split',
        'subtitle_box_gap',
        'inpaint_region',
        'inpaint_box_bg_color',
        'inpaint_box_bg_opacity',
        'inpaint_box_border_color',
        'inpaint_box_border_width',
        'inpaint_box_border_radius',
        'inpaint_show_box',
        'inpaint_engine',
        'secondary_lang',
      ];

  @override
  Future<Map<String, dynamic>> run(
    Directory workspace,
    Map<String, dynamic> config,
    JobState jobState,
  ) async {
    final srtFile = File(p.join(workspace.path, 'subtitles_vi.srt'));
    final assFile = File(p.join(workspace.path, 'subtitles_vi.ass'));

    final subCfg = config['subtitle'] is Map ? config['subtitle'] as Map : {};
    final subSecCfg = subCfg['secondary'] is Map ? subCfg['secondary'] as Map : {};
    final inpaintCfg = config['inpaint'] is Map ? config['inpaint'] as Map : {};
    final appCfg = config['app'] is Map ? config['app'] as Map : {};

    final showMaster = (config['show_subtitle'] ?? subCfg['show'] ?? true) == true;
    final showPrimary = (config['subtitle_show_primary'] ?? subCfg['show_primary'] ?? true) == true;
    final showSecondary = (config['subtitle_secondary_show'] ?? subSecCfg['show'] ?? true) == true;
    final showBox = (config['inpaint_show_box'] ?? inpaintCfg['show_box'] ?? true) == true;
    final secondaryLang = (config['secondary_lang'] ?? appCfg['secondary_lang'] ?? '').toString().trim();

    final order = (config['subtitle_order'] ?? subCfg['order'] ?? 'primary_top').toString().toLowerCase();
    final boxSplit = (config['subtitle_box_split'] ?? subCfg['box_split'] ?? false) == true;
    final boxGap = ((config['subtitle_box_gap'] ?? subCfg['box_gap'] ?? 8) as num).toDouble();

    if (!showMaster) {
      srtFile.writeAsStringSync('');
      assFile.writeAsStringSync('');
      return {
        'srt_file': srtFile.path,
        'ass_file': assFile.path,
        'segment_count': 0,
      };
    }

    final timingInfo = jobState.getStepOutput('s08c_timing') ?? {};
    final timingFile = timingInfo['timing_file'] as String?;
    final sourceFile = (timingFile != null && File(timingFile).existsSync())
        ? File(timingFile)
        : File(p.join(workspace.path, 's08_translation.json'));

    if (!sourceFile.existsSync()) {
      srtFile.writeAsStringSync('');
      assFile.writeAsStringSync('');
      return {
        'srt_file': srtFile.path,
        'ass_file': assFile.path,
        'segment_count': 0,
      };
    }

    final segments = (jsonDecode(sourceFile.readAsStringSync()) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final probeInfo = jobState.getStepOutput('s01_probe') ?? {};
    final videoWidth = (probeInfo['width'] as num?)?.toInt() ?? 1080;
    final videoHeight = (probeInfo['height'] as num?)?.toInt() ?? 1920;

    // Region resolution
    final detectInfo = jobState.getStepOutput('s03_subtitle_detect') ?? {};
    List<double> region = [0.60, 0.05, 0.70, 0.95];

    final cfgRegion = config['inpaint_region'] ?? inpaintCfg['region'];
    if (cfgRegion is List && cfgRegion.length == 4) {
      region = cfgRegion.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    } else if (detectInfo['burnin_region'] is List && (detectInfo['burnin_region'] as List).length == 4) {
      region = (detectInfo['burnin_region'] as List).map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    }

    final paddingY = double.tryParse((config['inpaint_padding_y'] ?? inpaintCfg['padding_y'] ?? config['blur_box_padding_y'])?.toString() ?? '0.005') ?? 0.005;

    final ymin = (region[0] - paddingY).clamp(0.0, 1.0);
    final xmin = region[1].clamp(0.0, 1.0);
    final ymax = (region[2] + paddingY).clamp(0.0, 1.0);
    final xmax = region[3].clamp(0.0, 1.0);

    final topPx = (ymin * videoHeight).round();
    final leftPx = (xmin * videoWidth).round();
    final bottomPx = (ymax * videoHeight).round();
    final rightPx = (xmax * videoWidth).round();
    final boxWidth = max(50, rightPx - leftPx);
    final boxHeight = max(30, bottomPx - topPx);
    final centerX = leftPx + boxWidth ~/ 2;
    final centerY = topPx + boxHeight ~/ 2;

    // Font and styling
    final fontName = (config['subtitle_font_name'] ?? subCfg['font_name'] ?? 'Arial').toString().trim().isNotEmpty
        ? (config['subtitle_font_name'] ?? subCfg['font_name'] ?? 'Arial').toString().trim()
        : 'Arial';
    final rawFs = (config['subtitle_font_size'] ?? subCfg['font_size'] as num?)?.toInt() ?? 35;
    final int fontSize;
    if (videoHeight > 1080) {
      fontSize = (rawFs * (videoHeight / 1080.0)).round();
    } else {
      fontSize = max(18, rawFs);
    }

    final fontColor = AssUtils.toAssColor(
      (config['subtitle_font_color'] ?? subCfg['font_color'])?.toString(),
      defaultColor: '&H00FFFFFF',
    );
    final outlineColor = AssUtils.toAssColor(
      (config['subtitle_outline_color'] ?? subCfg['outline_color'])?.toString(),
      defaultColor: '&H00000000',
    );

    // Secondary Font Styling
    final secFontNameRaw = (config['subtitle_secondary_font_name'] ?? subSecCfg['font_name'])?.toString().trim() ?? '';
    final secFontName = secFontNameRaw.isNotEmpty ? secFontNameRaw : fontName;
    final secFontScale = ((config['subtitle_secondary_font_size_scale'] ?? subSecCfg['font_size_scale'] ?? 0.75) as num).toDouble();
    final int secFontSize = max(18, (fontSize * secFontScale).round());
    final secFontColor = AssUtils.toAssColor(
      (config['subtitle_secondary_font_color'] ?? subSecCfg['font_color'])?.toString(),
      defaultColor: '&H00D0D0D0',
    );
    final secOutlineColor = AssUtils.toAssColor(
      (config['subtitle_secondary_outline_color'] ?? subSecCfg['outline_color'])?.toString(),
      defaultColor: '&H00000000',
    );

    // SubBox styling
    final inpaintEngine = (inpaintCfg['engine'] ?? config['inpaint_engine'] ?? 'box_color').toString().toLowerCase();
    final isBoxColor = (inpaintEngine == 'box_color' || inpaintEngine == 'box') && showBox;

    final boxCfg = inpaintCfg['box'] is Map ? inpaintCfg['box'] as Map : {};
    final boxBgOpacity = (config['inpaint_box_bg_opacity'] ?? boxCfg['bg_opacity'] as num?)?.toDouble() ?? 0.75;
    final boxBgColor = AssUtils.toAssColor(
      (config['inpaint_box_bg_color'] ?? boxCfg['bg_color'])?.toString(),
      defaultColor: '&H00000000',
      opacity: boxBgOpacity,
    );
    final boxBorderColor = AssUtils.toAssColor(
      (config['inpaint_box_border_color'] ?? boxCfg['border_color'])?.toString(),
      defaultColor: '&H40FFFFFF',
    );
    final boxBorderWidth = (config['inpaint_box_border_width'] ?? boxCfg['border_width'] as num?)?.toInt() ?? 2;
    final boxBorderRadius = (config['inpaint_box_border_radius'] ?? boxCfg['border_radius'] as num?)?.toInt() ?? 8;

    // 1. Generate SRT
    final srtBuffer = StringBuffer();
    int srtIndex = 1;
    final maxPriChars = (videoWidth <= 1080) ? 26 : 38;
    final maxSecChars = (videoWidth <= 1080) ? 36 : 50;

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final start = double.tryParse(seg['start']?.toString() ?? '0.0') ?? 0.0;
      final rawEnd = double.tryParse(seg['end']?.toString() ?? '') ?? (start + 1.0);
      final end = rawEnd > start ? rawEnd : (start + 0.5);

      final rawPri = showPrimary ? (seg['translated_text'] ?? seg['text_vi'] ?? seg['text'] ?? '').toString().trim() : '';
      final rawSec = (showSecondary && secondaryLang.isNotEmpty)
          ? (seg['text_secondary'] ?? seg['secondary_text'] ?? '').toString().trim()
          : '';

      if (rawPri.isEmpty && rawSec.isEmpty) continue;

      final primaryText = AssUtils.autoWrapText(rawPri, maxCharsPerLine: maxPriChars).replaceAll(r'\N', '\n');
      final secondaryText = AssUtils.autoWrapText(rawSec, maxCharsPerLine: maxSecChars).replaceAll(r'\N', '\n');

      srtBuffer.writeln('$srtIndex');
      srtBuffer.writeln('${_formatSrtTime(start)} --> ${_formatSrtTime(end)}');
      if (primaryText.isNotEmpty && secondaryText.isNotEmpty) {
        if (order == 'secondary_top') {
          srtBuffer.writeln(secondaryText);
          srtBuffer.writeln(primaryText);
        } else {
          srtBuffer.writeln(primaryText);
          srtBuffer.writeln(secondaryText);
        }
      } else {
        srtBuffer.writeln(primaryText.isNotEmpty ? primaryText : secondaryText);
      }
      srtBuffer.writeln();
      srtIndex++;
    }
    srtFile.writeAsStringSync(srtBuffer.toString());

    // 2. Generate ASS
    final marginL = max(40, (videoWidth * 0.08).round());
    final marginR = max(40, (videoWidth * 0.08).round());
    final marginV = max(20, (videoHeight * 0.03).round());

    final assBuffer = StringBuffer();
    assBuffer.writeln('[Script Info]');
    assBuffer.writeln('ScriptType: v4.00+');
    assBuffer.writeln('PlayResX: $videoWidth');
    assBuffer.writeln('PlayResY: $videoHeight');
    assBuffer.writeln('ScaledBorderAndShadow: yes');
    assBuffer.writeln();
    assBuffer.writeln('[V4+ Styles]');
    assBuffer.writeln('Style: SubText,$fontName,$fontSize,$fontColor,&H000000FF,$outlineColor,&H80000000,1,0,0,0,100,100,0,0,1,2,1,5,$marginL,$marginR,$marginV,1');
    assBuffer.writeln('Style: SubTextSecondary,$secFontName,$secFontSize,$secFontColor,&H000000FF,$secOutlineColor,&H80000000,1,0,0,0,100,100,0,0,1,2,1,5,$marginL,$marginR,$marginV,1');
    assBuffer.writeln('Style: SubBox,Arial,$fontSize,$boxBgColor,&H000000FF,$boxBorderColor,&H00000000,0,0,0,0,100,100,0,0,1,$boxBorderWidth,0,5,0,0,0,1');
    assBuffer.writeln();
    assBuffer.writeln('[Events]');
    assBuffer.writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');

    // Secondary Region resolution
    final secRegionCfg = subSecCfg['region'] ?? config['subtitle_secondary_region'];
    List<double>? secRegion;
    if (secRegionCfg is List && secRegionCfg.length == 4) {
      secRegion = secRegionCfg.map((e) => double.tryParse(e.toString()) ?? 0.0).toList();
    }

    final bool hasIndependentSecRegion = secRegion != null;
    int secCenterX = centerX;
    int secCenterY = centerY;
    int secBoxWidth = boxWidth;
    int secBoxHeight = boxHeight;
    String secBoxVectorPath = '';

    if (hasIndependentSecRegion) {
      final secTopPx = (secRegion[0] * videoHeight).round();
      final secLeftPx = (secRegion[1] * videoWidth).round();
      final secBottomPx = (secRegion[2] * videoHeight).round();
      final secRightPx = (secRegion[3] * videoWidth).round();
      secBoxWidth = max(50, secRightPx - secLeftPx);
      secBoxHeight = max(30, secBottomPx - secTopPx);
      secCenterX = secLeftPx + secBoxWidth ~/ 2;
      secCenterY = secTopPx + secBoxHeight ~/ 2;
      secBoxVectorPath = AssUtils.makeBoxPath(secBoxWidth, secBoxHeight, boxBorderRadius);
    }

    final boxVectorPath = AssUtils.makeBoxPath(boxWidth, boxHeight, boxBorderRadius);

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final start = double.tryParse(seg['start']?.toString() ?? '0.0') ?? 0.0;
      final rawEnd = double.tryParse(seg['end']?.toString() ?? '') ?? (start + 1.0);
      final end = rawEnd > start ? rawEnd : (start + 0.5);

      final rawPri = showPrimary ? (seg['translated_text'] ?? seg['text_vi'] ?? seg['text'] ?? '').toString().trim() : '';
      final rawSec = (showSecondary && secondaryLang.isNotEmpty)
          ? (seg['text_secondary'] ?? seg['secondary_text'] ?? '').toString().trim()
          : '';

      if (rawPri.isEmpty && rawSec.isEmpty) continue;

      final primaryText = AssUtils.autoWrapText(rawPri, maxCharsPerLine: maxPriChars);
      final secondaryText = AssUtils.autoWrapText(rawSec, maxCharsPerLine: maxSecChars);

      final textTimeStart = AssUtils.formatAssTime(start);
      final textTimeEnd = AssUtils.formatAssTime(end);

      if (hasIndependentSecRegion) {
        // Independent dual positions (Primary at Bottom, Secondary at Custom Top Region)
        if (primaryText.isNotEmpty) {
          if (isBoxColor) {
            assBuffer.writeln('Dialogue: 0,$textTimeStart,$textTimeEnd,SubBox,,0,0,0,,{\\an5\\pos($centerX,$centerY)\\p1\\bord$boxBorderWidth\\3c$boxBorderColor\\1c$boxBgColor}$boxVectorPath{\\p0}');
          }
          assBuffer.writeln('Dialogue: 1,$textTimeStart,$textTimeEnd,SubText,,0,0,0,,{\\an5\\pos($centerX,$centerY)}$primaryText');
        }

        if (secondaryText.isNotEmpty) {
          if (isBoxColor) {
            assBuffer.writeln('Dialogue: 0,$textTimeStart,$textTimeEnd,SubBox,,0,0,0,,{\\an5\\pos($secCenterX,$secCenterY)\\p1\\bord$boxBorderWidth\\3c$boxBorderColor\\1c$boxBgColor}$secBoxVectorPath{\\p0}');
          }
          assBuffer.writeln('Dialogue: 1,$textTimeStart,$textTimeEnd,SubTextSecondary,,0,0,0,,{\\an5\\pos($secCenterX,$secCenterY)}$secondaryText');
        }
      } else if (secondaryText.isNotEmpty && primaryText.isNotEmpty) {
        // Dual Subtitles Dynamic Stacking with Line-Aware Height & Gap
        final priLines = primaryText.split(RegExp(r'\\N|\n')).length;
        final secLines = secondaryText.split(RegExp(r'\\N|\n')).length;

        final lhPri = priLines * fontSize * 1.20;
        final lhSec = secLines * secFontSize * 1.20;
        final scaledGap = (boxGap * (videoHeight / 1080.0)).clamp(18.0, 48.0);
        final gap = max(18.0, scaledGap);
        final totalH = lhPri + lhSec + gap;

        int cyPri, cySec;
        int hTop, hBot;
        if (order == 'secondary_top') {
          cySec = (centerY - (totalH / 2.0) + (lhSec / 2.0)).round();
          cyPri = (centerY + (totalH / 2.0) - (lhPri / 2.0)).round();
          hTop = (lhSec + 12).round();
          hBot = (lhPri + 14).round();
        } else {
          cyPri = (centerY - (totalH / 2.0) + (lhPri / 2.0)).round();
          cySec = (centerY + (totalH / 2.0) - (lhSec / 2.0)).round();
          hTop = (lhPri + 14).round();
          hBot = (lhSec + 12).round();
        }

        // Layer 0: SubBox
        if (isBoxColor) {
          if (boxSplit) {
            final pathTop = AssUtils.makeBoxPath(boxWidth, hTop, boxBorderRadius);
            final pathBot = AssUtils.makeBoxPath(boxWidth, hBot, boxBorderRadius);
            final cyTop = order == 'secondary_top' ? cySec : cyPri;
            final cyBot = order == 'secondary_top' ? cyPri : cySec;
            assBuffer.writeln('Dialogue: 0,$textTimeStart,$textTimeEnd,SubBox,,0,0,0,,{\\an5\\pos($centerX,$cyTop)\\p1\\bord$boxBorderWidth\\3c$boxBorderColor\\1c$boxBgColor}$pathTop{\\p0}');
            assBuffer.writeln('Dialogue: 0,$textTimeStart,$textTimeEnd,SubBox,,0,0,0,,{\\an5\\pos($centerX,$cyBot)\\p1\\bord$boxBorderWidth\\3c$boxBorderColor\\1c$boxBgColor}$pathBot{\\p0}');
          } else {
            assBuffer.writeln('Dialogue: 0,$textTimeStart,$textTimeEnd,SubBox,,0,0,0,,{\\an5\\pos($centerX,$centerY)\\p1\\bord$boxBorderWidth\\3c$boxBorderColor\\1c$boxBgColor}$boxVectorPath{\\p0}');
          }
        }

        // Layer 1: SubText
        assBuffer.writeln('Dialogue: 1,$textTimeStart,$textTimeEnd,SubText,,0,0,0,,{\\an5\\pos($centerX,$cyPri)}$primaryText');
        assBuffer.writeln('Dialogue: 1,$textTimeStart,$textTimeEnd,SubTextSecondary,,0,0,0,,{\\an5\\pos($centerX,$cySec)}$secondaryText');
      } else {
        // Single subtitle centered
        final activeText = primaryText.isNotEmpty ? primaryText : secondaryText;
        final activeStyle = primaryText.isNotEmpty ? 'SubText' : 'SubTextSecondary';

        if (isBoxColor) {
          assBuffer.writeln('Dialogue: 0,$textTimeStart,$textTimeEnd,SubBox,,0,0,0,,{\\an5\\pos($centerX,$centerY)\\p1\\bord$boxBorderWidth\\3c$boxBorderColor\\1c$boxBgColor}$boxVectorPath{\\p0}');
        }
        assBuffer.writeln('Dialogue: 1,$textTimeStart,$textTimeEnd,$activeStyle,,0,0,0,,{\\an5\\pos($centerX,$centerY)}$activeText');
      }
    }

    assFile.writeAsStringSync(assBuffer.toString());

    return {
      'srt_file': srtFile.path,
      'ass_file': assFile.path,
      'segment_count': segments.length,
    };
  }

  String _formatSrtTime(double seconds) {
    if (seconds < 0) seconds = 0;
    final totalMs = (seconds * 1000).round();
    final ms = totalMs % 1000;
    final totalSeconds = totalMs ~/ 1000;
    final s = totalSeconds % 60;
    final m = (totalSeconds ~/ 60) % 60;
    final h = totalSeconds ~/ 3600;

    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    final mmm = ms.toString().padLeft(3, '0');

    return '$hh:$mm:$ss,$mmm';
  }
}
