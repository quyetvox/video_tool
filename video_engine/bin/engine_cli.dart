import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:video_engine/video_engine.dart';
import 'package:yaml/yaml.dart';

List<StepBase> get defaultSteps => [
      StepProbe(),
      StepDemux(),
      StepSubtitleDetect(),
      StepAudioSeparate(),
      StepASR(),
      StepGenderDetect(),
      StepOCR(),
      StepTranscriptMerge(),
      StepTranslation(),
      StepMetadataGen(),
      StepTiming(),
      StepSubtitleGen(),
      StepInpaint(),
      StepSubtitleRender(),
      StepTTS(),
      StepAudioMix(),
      StepEncode(),
    ];

void main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final command = args[0];
  try {
    switch (command) {
      case 'status':
        await _handleStatus(args.sublist(1));
        break;
      case 'translate':
        await _handleTranslate(args.sublist(1));
        break;
      case 'run-step':
        await _handleRunStep(args.sublist(1));
        break;
      case 'delete-step':
        await _handleDeleteStep(args.sublist(1));
        break;
      case 'delete-job':
        await _handleDeleteJob(args.sublist(1));
        break;
      default:
        _emitJson({'type': 'error', 'message': 'Unknown command: $command'});
        exit(1);
    }
  } catch (e, st) {
    _emitJson({
      'type': 'error',
      'message': e.toString(),
      'stack_trace': st.toString(),
    });
    exit(1);
  }
}

void _printUsage() {
  stderr.writeln('''
Sub-Video AI Sidecar Engine CLI
Usage:
  engine_cli status <project_dir> <job_id>
  engine_cli translate <project_dir> <video_file> [--voice|--ocr-only]
  engine_cli run-step <project_dir> <job_id> <step_id>
  engine_cli delete-step <project_dir> <job_id> <step_id>
  engine_cli delete-job <project_dir> <job_id>
''');
}

void _emitJson(Map<String, dynamic> data) {
  stdout.writeln(jsonEncode(data));
}

Map<String, dynamic> _loadRawConfig(Directory projectDir) {
  final cfgFile = File(p.join(projectDir.path, 'config.yaml'));
  if (!cfgFile.existsSync()) {
    return <String, dynamic>{};
  }
  final rawYaml = loadYaml(cfgFile.readAsStringSync());
  dynamic convert(dynamic val) {
    if (val is YamlMap) {
      return val.map((k, v) => MapEntry(k.toString(), convert(v)));
    } else if (val is YamlList) {
      return val.map(convert).toList();
    }
    return val;
  }
  return Map<String, dynamic>.from(convert(rawYaml) as Map? ?? {});
}

Future<void> _handleStatus(List<String> args) async {
  if (args.length < 2) {
    _emitJson({'type': 'error', 'message': 'Usage: status <project_dir> <job_id>'});
    exit(1);
  }
  final projectDir = Directory(args[0]);
  final jobId = args[1];
  final wsDir = Directory(p.join(projectDir.path, 'workspace', jobId));
  final stateFile = File(p.join(wsDir.path, 'state.json'));

  if (!stateFile.existsSync()) {
    _emitJson({
      'type': 'status_result',
      'job_id': jobId,
      'status': 'not_found',
      'steps': {},
    });
    return;
  }

  final state = jsonDecode(stateFile.readAsStringSync());
  _emitJson({
    'type': 'status_result',
    'job_id': jobId,
    'status': state['status'] ?? 'pending',
    'steps': state['steps'] ?? {},
    'video_info': state['video_info'] ?? {},
  });
}

Future<void> _handleDeleteStep(List<String> args) async {
  if (args.length < 3) {
    _emitJson({'type': 'error', 'message': 'Usage: delete-step <project_dir> <job_id> <step_id>'});
    exit(1);
  }
  final projectDir = Directory(args[0]);
  final jobId = args[1];
  final stepId = args[2];
  final wsDir = Directory(p.join(projectDir.path, 'workspace'));
  final jobState = JobState(workspace: wsDir, jobId: jobId);

  final cleared = jobState.clearStep(stepId);
  _emitJson({
    'type': 'step_deleted',
    'job_id': jobId,
    'step_id': stepId,
    'affected_steps': cleared,
    'status': 'success',
  });
}

Future<void> _handleDeleteJob(List<String> args) async {
  if (args.length < 2) {
    _emitJson({'type': 'error', 'message': 'Usage: delete-job <project_dir> <job_id>'});
    exit(1);
  }
  final projectDir = Directory(args[0]);
  final jobId = args[1];
  final jobDir = Directory(p.join(projectDir.path, 'workspace', jobId));

  if (jobDir.existsSync()) {
    jobDir.deleteSync(recursive: true);
  }
  _emitJson({
    'type': 'job_deleted',
    'job_id': jobId,
    'status': 'success',
  });
}

Future<void> _handleRunStep(List<String> args) async {
  if (args.length < 3) {
    _emitJson({'type': 'error', 'message': 'Usage: run-step <project_dir> <job_id> <step_id>'});
    exit(1);
  }
  final projectDir = Directory(args[0]);
  final jobId = args[1];
  final stepId = args[2];
  final rawConfig = _loadRawConfig(projectDir);
  final wsDir = Directory(p.join(projectDir.path, 'workspace'));
  final jobState = JobState(workspace: wsDir, jobId: jobId);

  final targetStep = defaultSteps.firstWhere(
    (s) => s.stepId == stepId,
    orElse: () => throw Exception('Step not found: $stepId'),
  );

  _emitJson({
    'type': 'step_started',
    'job_id': jobId,
    'step_id': stepId,
  });

  final result = await targetStep.run(jobState.jobDir, rawConfig, jobState);
  jobState.setStepStatus(stepId, 'done', output: result);

  _emitJson({
    'type': 'step_completed',
    'job_id': jobId,
    'step_id': stepId,
    'output': result,
  });
}

Future<void> _handleTranslate(List<String> args) async {
  if (args.length < 2) {
    _emitJson({'type': 'error', 'message': 'Usage: translate <project_dir> <video_file> [--voice|--ocr-only]'});
    exit(1);
  }
  final projectDir = Directory(args[0]);
  final videoFile = File(args[1]);
  final isVoiceForced = args.contains('--voice');
  final isOcrForced = args.contains('--ocr-only');

  if (!videoFile.existsSync()) {
    _emitJson({'type': 'error', 'message': 'Video file not found: ${videoFile.path}'});
    exit(1);
  }

  final rawConfig = _loadRawConfig(projectDir);
  if (isVoiceForced) {
    rawConfig['app'] ??= <String, dynamic>{};
    if (rawConfig['app'] is Map) {
      (rawConfig['app'] as Map)['ocr_only'] = false;
    }
    rawConfig['ocr_only'] = false;
  } else if (isOcrForced) {
    rawConfig['app'] ??= <String, dynamic>{};
    if (rawConfig['app'] is Map) {
      (rawConfig['app'] as Map)['ocr_only'] = true;
    }
    rawConfig['ocr_only'] = true;
  }

  final config = ConfigDict(rawConfig);
  final projectPaths = ProjectManager.resolveProjectPaths(projectDir.path);
  final resolvedVideo = ProjectManager.resolveSourceVideo(videoFile.path, projectDir: projectPaths.projectDir);
  final jobId = ProjectManager.getJobId(resolvedVideo.path);
  final wsDir = projectPaths.workspaceDir;

  final jobState = JobState(
    workspace: wsDir,
    jobId: jobId,
    inputVideo: resolvedVideo.path,
    config: rawConfig,
  );

  final runner = PipelineRunner(
    steps: defaultSteps,
    onLog: (stepId, msg, {type = 'info'}) {
      _emitJson({
        'type': 'log',
        'step_id': stepId,
        'message': msg,
        'level': type,
      });
    },
    onStepStatus: (stepId, status, progress) {
      _emitJson({
        'type': 'step_status',
        'step_id': stepId,
        'status': status,
        'progress': progress,
      });
    },
  );

  _emitJson({
    'type': 'job_started',
    'job_id': jobId,
    'video_path': videoFile.path,
    'project_path': projectDir.path,
  });

  final success = await runner.run(jobState, config);
  final encodeOut = jobState.getStepOutput('s14_encode') ?? {};

  _emitJson({
    'type': 'job_completed',
    'job_id': jobId,
    'success': success,
    'status': jobState.data['status'] ?? (success ? 'completed' : 'failed'),
    'output_file': encodeOut['output_file'] ?? '',
  });
}
