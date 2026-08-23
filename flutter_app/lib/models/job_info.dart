class LogEntry {
  final String id;
  final String type; // stdout | stderr | system-info | system-success | system-error
  final String text;
  final String time;
  final String jobId;

  const LogEntry({
    required this.id,
    required this.type,
    required this.text,
    required this.time,
    required this.jobId,
  });

  bool get isError => type == 'stderr' || type == 'system-error';
  bool get isSuccess => type == 'system-success';
  bool get isInfo => type == 'system-info';
  String get message => text;
  String get timeStr => time;
  String get level => type;
}

class JobInfo {
  final String jobId;
  final String script;
  final List<String> args;
  final DateTime startTime;
  final bool isRunning;
  final int? exitCode;
  final bool success;
  final String? error;

  const JobInfo({
    required this.jobId,
    required this.script,
    required this.args,
    required this.startTime,
    this.isRunning = true,
    this.exitCode,
    this.success = false,
    this.error,
  });

  JobInfo copyWith({
    bool? isRunning,
    int? exitCode,
    bool? success,
    String? error,
  }) {
    return JobInfo(
      jobId: jobId,
      script: script,
      args: args,
      startTime: startTime,
      isRunning: isRunning ?? this.isRunning,
      exitCode: exitCode ?? this.exitCode,
      success: success ?? this.success,
      error: error ?? this.error,
    );
  }
}
