class ProjectInfo {
  final String name;
  final bool hasConfig;
  final int srcCount;
  final int cutCount;
  final int mergeCount;
  final int workspaceCount;
  final int outputCount;

  const ProjectInfo({
    required this.name,
    required this.hasConfig,
    this.srcCount = 0,
    this.cutCount = 0,
    this.mergeCount = 0,
    this.workspaceCount = 0,
    this.outputCount = 0,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    return ProjectInfo(
      name: json['name'] as String? ?? '',
      hasConfig: json['hasConfig'] as bool? ?? false,
      srcCount: json['srcCount'] as int? ?? 0,
      cutCount: json['cutCount'] as int? ?? 0,
      mergeCount: json['mergeCount'] as int? ?? 0,
      workspaceCount: json['workspaceCount'] as int? ?? 0,
      outputCount: json['outputCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'hasConfig': hasConfig,
        'srcCount': srcCount,
        'cutCount': cutCount,
        'mergeCount': mergeCount,
        'workspaceCount': workspaceCount,
        'outputCount': outputCount,
      };
}
